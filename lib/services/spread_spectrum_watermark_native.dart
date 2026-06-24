import 'dart:math' as math;
import 'dart:typed_data';

/// Pure-Dart spread-spectrum audio watermarking.
///
/// Embeds an imperceptible pseudorandom pattern in the frequency domain.
/// Cross-compatible with CrispASR's `crispasr_watermark.h` and CrispTTS's
/// `watermark.py` — all three use the same xoshiro128+ PRNG, bin pattern
/// generation, and STFT overlap-add approach.
///
/// The watermark survives moderate lossy compression (MP3 128k+) and
/// resampling. It does NOT survive aggressive re-encoding below ~64 kbps
/// or adversarial spectral manipulation.
class SpreadSpectrumWatermark {
  SpreadSpectrumWatermark._();

  /// Watermark key — must match CrispASR's WATERMARK_KEY.
  static const int key = 0x437269737041535F; // "CrispASR" in hex

  /// Number of frequency bins to modify per frame.
  static const int nBins = 32;

  static const int _fftSize = 1024;
  static const int _hop = _fftSize ~/ 2;

  /// Embed a spread-spectrum watermark into [pcm] (mono float32).
  ///
  /// [alpha] controls watermark strength (0.08 = ~38 dB SNR, imperceptible).
  /// Returns a new array; the input is not modified.
  static Float32List embed(Float32List pcm, {double alpha = 0.08}) {
    final n = pcm.length;
    if (n < _fftSize) return Float32List.fromList(pcm);

    final bins = _generateBinPattern(key, _fftSize, nBins);
    if (bins.isEmpty) return Float32List.fromList(pcm);

    final window = _hanningWindow(_fftSize);
    final out = Float64List(n); // accumulator
    final norm = Float64List(n); // normalization

    for (var start = 0; start + _fftSize <= n; start += _hop) {
      // Window the frame
      final frame = Float64List(_fftSize);
      for (var i = 0; i < _fftSize; i++) {
        frame[i] = pcm[start + i] * window[i];
      }

      // Forward FFT (real → complex)
      final spectrum = _rfft(frame);

      // RMS magnitude for energy-proportional nudge
      var sumSq = 0.0;
      var count = 0;
      for (var i = 1; i < _fftSize ~/ 2; i++) {
        final mag = _complexAbs(spectrum[i * 2], spectrum[i * 2 + 1]);
        sumSq += mag * mag;
        count++;
      }
      final rmsMag = count > 0 ? math.sqrt(sumSq / count) : 0.0;
      final nudge = alpha * rmsMag;

      // Apply watermark to selected bins
      for (final bp in bins) {
        final idx = bp.bin;
        final sign = bp.sign;
        if (idx * 2 + 1 >= spectrum.length) continue;

        final re = spectrum[idx * 2];
        final im = spectrum[idx * 2 + 1];
        final mag = _complexAbs(re, im);
        final newMag = math.max(mag + nudge * sign, 0.0);

        if (mag > 1e-15) {
          final scale = newMag / mag;
          spectrum[idx * 2] *= scale;
          spectrum[idx * 2 + 1] *= scale;
        } else if (sign > 0) {
          spectrum[idx * 2] = nudge;
          spectrum[idx * 2 + 1] = 0.0;
        }
      }

      // Inverse FFT
      final reconstructed = _irfft(spectrum, _fftSize);

      // Overlap-add
      for (var i = 0; i < _fftSize; i++) {
        out[start + i] += reconstructed[i] * window[i];
        norm[start + i] += window[i] * window[i];
      }
    }

    // Normalize and produce output
    final result = Float32List(n);
    for (var i = 0; i < n; i++) {
      if (norm[i] > 1e-8) {
        result[i] = out[i] / norm[i];
      } else {
        result[i] = pcm[i];
      }
    }
    return result;
  }

  /// Detect spread-spectrum watermark in [pcm].
  ///
  /// Returns confidence 0.0 (absent) to 1.0 (present).
  /// Scores >0.65 indicate watermark present; <0.4 absent.
  static double detect(Float32List pcm) {
    final n = pcm.length;
    if (n < _fftSize) return 0.0;

    final bins = _generateBinPattern(key, _fftSize, nBins);
    if (bins.isEmpty) return 0.0;

    final window = _hanningWindow(_fftSize);
    final nHalf = _fftSize ~/ 2;

    // Accumulate averaged magnitude spectrum
    final avgMags = Float64List(nHalf);
    var frameCount = 0;

    for (var start = 0; start + _fftSize <= n; start += _hop) {
      final frame = Float64List(_fftSize);
      for (var i = 0; i < _fftSize; i++) {
        frame[i] = pcm[start + i] * window[i];
      }
      final spectrum = _rfft(frame);
      for (var i = 0; i < nHalf; i++) {
        avgMags[i] += _complexAbs(spectrum[i * 2], spectrum[i * 2 + 1]);
      }
      frameCount++;
    }
    if (frameCount == 0) return 0.0;
    for (var i = 0; i < nHalf; i++) {
      avgMags[i] /= frameCount;
    }

    // Correlate watermark pattern against averaged spectrum
    var correlation = 0.0;
    var validBins = 0;

    for (final bp in bins) {
      final idx = bp.bin;
      if (idx >= nHalf) continue;

      // Local mean of ±2 neighbours (excluding self)
      var localSum = 0.0;
      var localCount = 0;
      for (var d = -2; d <= 2; d++) {
        final nb = idx + d;
        if (nb >= 1 && nb < nHalf && d != 0) {
          localSum += avgMags[nb];
          localCount++;
        }
      }
      if (localCount == 0) continue;
      final localMean = localSum / localCount;
      if (localMean < 1e-12 && avgMags[idx] < 1e-12) continue;

      final ref = math.max(localMean, 1e-12);
      final delta = (avgMags[idx] - localMean) / ref;
      correlation += (delta > 0 ? 1.0 : -1.0) * bp.sign;
      validBins++;
    }

    if (validBins == 0) return 0.0;
    return ((correlation / validBins + 1.0) / 2.0).clamp(0.0, 1.0);
  }

  // ------------------------------------------------------------------
  // xoshiro128+ PRNG (matches CrispASR's crispasr_wm::prng)
  // ------------------------------------------------------------------

  static List<_BinPattern> _generateBinPattern(int key, int nFft, int nBins) {
    final rng = _Prng(key);
    final loBin = nFft ~/ 16;
    final hiBin = nFft ~/ 2 - 1;
    final span = hiBin - loBin;
    if (span <= 0 || nBins <= 0) return [];
    final bins = <_BinPattern>[];
    for (var i = 0; i < nBins; i++) {
      final idx = loBin + rng.nextU32(span);
      final sign = (rng.next() & 1) == 1 ? 1 : -1;
      bins.add(_BinPattern(idx, sign));
    }
    return bins;
  }

  static Float64List _hanningWindow(int n) {
    final w = Float64List(n);
    for (var i = 0; i < n; i++) {
      w[i] = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / n));
    }
    return w;
  }

  static double _complexAbs(double re, double im) =>
      math.sqrt(re * re + im * im);

  // ------------------------------------------------------------------
  // Minimal real-valued FFT (Cooley-Tukey radix-2 DIT)
  // ------------------------------------------------------------------

  /// Real FFT: [n] real samples → [n+2] interleaved complex (re,im pairs).
  /// Only the non-redundant half (0..n/2) is returned.
  static Float64List _rfft(Float64List x) {
    final n = x.length;
    // Full complex FFT on the real input packed as complex with im=0.
    final c = Float64List(n * 2);
    for (var i = 0; i < n; i++) {
      c[i * 2] = x[i];
    }
    _fftInPlace(c, false);
    // Return only the first n/2+1 complex values.
    return Float64List.fromList(c.sublist(0, n + 2));
  }

  /// Inverse real FFT: [n+2] interleaved complex → [n] real samples.
  static Float64List _irfft(Float64List spectrum, int n) {
    final c = Float64List(n * 2);
    // Copy the non-redundant half.
    for (var i = 0; i < n + 2 && i < spectrum.length; i++) {
      c[i] = spectrum[i];
    }
    // Mirror the conjugate half.
    for (var i = 1; i < n ~/ 2; i++) {
      c[(n - i) * 2] = c[i * 2];
      c[(n - i) * 2 + 1] = -c[i * 2 + 1];
    }
    _fftInPlace(c, true);
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      out[i] = c[i * 2] / n;
    }
    return out;
  }

  /// In-place radix-2 Cooley-Tukey FFT on interleaved complex [data].
  static void _fftInPlace(Float64List data, bool inverse) {
    final n = data.length ~/ 2;
    // Bit-reversal permutation.
    var j = 0;
    for (var i = 0; i < n; i++) {
      if (i < j) {
        final tr = data[j * 2];
        final ti = data[j * 2 + 1];
        data[j * 2] = data[i * 2];
        data[j * 2 + 1] = data[i * 2 + 1];
        data[i * 2] = tr;
        data[i * 2 + 1] = ti;
      }
      var m = n >> 1;
      while (m >= 1 && j >= m) {
        j -= m;
        m >>= 1;
      }
      j += m;
    }
    // Butterfly stages.
    final sign = inverse ? 1.0 : -1.0;
    for (var step = 1; step < n; step <<= 1) {
      final angleStep = sign * math.pi / step;
      final wRe = math.cos(angleStep);
      final wIm = math.sin(angleStep);
      for (var group = 0; group < n; group += step << 1) {
        var curRe = 1.0;
        var curIm = 0.0;
        for (var pair = 0; pair < step; pair++) {
          final a = (group + pair) * 2;
          final b = (group + pair + step) * 2;
          final tRe = curRe * data[b] - curIm * data[b + 1];
          final tIm = curRe * data[b + 1] + curIm * data[b];
          data[b] = data[a] - tRe;
          data[b + 1] = data[a + 1] - tIm;
          data[a] += tRe;
          data[a + 1] += tIm;
          final newRe = curRe * wRe - curIm * wIm;
          curIm = curRe * wIm + curIm * wRe;
          curRe = newRe;
        }
      }
    }
  }
}

class _BinPattern {
  final int bin;
  final int sign;
  const _BinPattern(this.bin, this.sign);
}

/// xoshiro128+ PRNG matching CrispASR's crispasr_wm::prng.
class _Prng {
  int _s0;
  int _s1;

  _Prng(int seed) : _s0 = 0, _s1 = 0 {
    final (state1, hash1) = _splitmix64(seed);
    final (_, hash2) = _splitmix64(hash1);
    _s0 = state1;
    _s1 = hash2;
  }

  static (int, int) _splitmix64(int x) {
    x = (x + 0x9E3779B97F4A7C15) & _mask;
    var z = x;
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & _mask;
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & _mask;
    return (x, (z ^ (z >> 31)) & _mask);
  }

  int next() {
    final s0 = _s0;
    var s1 = _s1;
    final result = (s0 + s1) & _mask;
    s1 ^= s0;
    _s0 = (((s0 << 55) | (s0 >>> 9)) & _mask) ^ s1 ^ ((s1 << 14) & _mask);
    _s1 = ((s1 << 36) | (s1 >>> 28)) & _mask;
    return result;
  }

  int nextU32(int bound) => next() % bound;

  static const int _mask = 0xFFFFFFFFFFFFFFFF;
}
