package com.crispstrobe.crisperweaver

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.projection.MediaProjectionManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {

    // §5.1.1 system-audio capture
    // ------------------------------------------------------------
    private val controlChannelName = "crisperweaver/system_audio_capture"
    private val streamChannelName =
        "crisperweaver/system_audio_capture/stream"
    private val mediaProjectionRequestCode = 7311

    // The result from the most recent start() call. We hold the
    // pending Flutter MethodChannel result so we can complete it
    // asynchronously from onActivityResult — Flutter doesn't let
    // us block in the MethodCallHandler.
    private var pendingStartResult: MethodChannel.Result? = null
    // EventSink for streaming PCM frames back to Dart. Bound by
    // the EventChannel's onListen callback.
    private var sink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val control = MethodChannel(messenger, controlChannelName)
        val stream = EventChannel(messenger, streamChannelName)

        stream.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
            }
            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })

        control.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> {
                    // AudioPlaybackCaptureConfiguration needs API 29 (Android 10).
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                }
                "start" -> startSystemAudioCapture(result)
                "stop" -> {
                    stopSystemAudioCapture()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Audio decode channel — transcode opus/m4a/aac/webm to 16 kHz
        // mono PCM WAV via Android's MediaExtractor + MediaCodec.
        val audioDecode = MethodChannel(messenger, "crisperweaver/audio_decode")
        audioDecode.setMethodCallHandler { call, result ->
            when (call.method) {
                "decodeToWav" -> {
                    val filePath = call.argument<String>("path")
                    if (filePath == null) {
                        result.error("bad_args", "missing 'path'", null)
                        return@setMethodCallHandler
                    }
                    thread {
                        try {
                            val wav = decodeToMonoWav(filePath, 16000)
                            runOnUiThread { result.success(wav) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("decode_failed", e.message, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /// Launches the MediaProjection permission intent and stashes
    /// the pending Flutter result. Completion happens in
    /// onActivityResult below.
    private fun startSystemAudioCapture(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error(
                "os_too_old",
                "System audio capture requires Android 10 (API 29) or later",
                null
            )
            return
        }
        if (pendingStartResult != null) {
            result.error(
                "already_starting",
                "Another start() is already in flight",
                null
            )
            return
        }
        // Hook the foreground service's frame-listener so PCM
        // arrives at our event sink. Set BEFORE we ask the user
        // for permission so the service has it the moment the
        // foreground intent lands.
        // Kotlin: lambdas assigned to properties have no implicit
        // label, so `return@frameListener` won't compile. Use a
        // small lambda factory with an explicit name so we can
        // early-out cleanly.
        val listener: (FloatArray) -> Unit = inner@{ samples ->
            val sinkLocal = sink ?: return@inner
            // Float32 → bytes (little-endian) for the wire. The
            // Dart side reinterprets via Float32List.view, which
            // is zero-copy.
            val bb = ByteBuffer
                .allocate(samples.size * 4)
                .order(ByteOrder.LITTLE_ENDIAN)
            for (s in samples) bb.putFloat(s)
            val bytes = bb.array()
            runOnUiThread {
                try {
                    sinkLocal.success(bytes)
                } catch (_: Throwable) {
                    // Sink may be cancelled mid-frame; ignore.
                }
            }
        }
        SystemAudioCaptureForegroundService.frameListener = listener

        pendingStartResult = result
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                as MediaProjectionManager
        val permIntent = mpm.createScreenCaptureIntent()
        try {
            startActivityForResult(permIntent, mediaProjectionRequestCode)
        } catch (e: Exception) {
            pendingStartResult = null
            SystemAudioCaptureForegroundService.frameListener = null
            result.error("start_failed", e.message ?: "start failed", null)
        }
    }

    private fun stopSystemAudioCapture() {
        val svc = Intent(this, SystemAudioCaptureForegroundService::class.java)
            .apply {
                action = SystemAudioCaptureForegroundService.ACTION_STOP
            }
        try {
            stopService(svc)
        } catch (_: Exception) {}
        SystemAudioCaptureForegroundService.frameListener = null
    }

    @Deprecated("Use registerForActivityResult — kept for plugin parity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != mediaProjectionRequestCode) return
        val pending = pendingStartResult
        pendingStartResult = null
        if (pending == null) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            SystemAudioCaptureForegroundService.frameListener = null
            pending.error(
                "permission_denied",
                "User declined screen + audio capture",
                null
            )
            return
        }
        // Hand the token to the foreground service. The service is
        // what holds the MediaProjection + AudioRecord; the activity
        // would lose them on screen rotation otherwise.
        val svc = Intent(this, SystemAudioCaptureForegroundService::class.java)
            .apply {
                action = SystemAudioCaptureForegroundService.ACTION_START
                putExtra(
                    SystemAudioCaptureForegroundService.EXTRA_RESULT_CODE,
                    resultCode
                )
                putExtra(
                    SystemAudioCaptureForegroundService.EXTRA_RESULT_DATA,
                    data
                )
            }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(this, svc)
            } else {
                startService(svc)
            }
            pending.success(true)
        } catch (e: Exception) {
            SystemAudioCaptureForegroundService.frameListener = null
            pending.error(
                "start_failed",
                e.message ?: "startForegroundService failed",
                null
            )
        }
    }

    /// Decode any audio file Android can handle (opus, m4a, aac, webm,
    /// mp4, wma…) to a 16 kHz mono 16-bit PCM WAV byte array using
    /// MediaExtractor + MediaCodec. Runs on a background thread.
    private fun decodeToMonoWav(filePath: String, targetSr: Int): ByteArray {
        val extractor = MediaExtractor()
        extractor.setDataSource(filePath)

        // Find the first audio track.
        var trackIndex = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val tf = extractor.getTrackFormat(i)
            if (tf.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                trackIndex = i
                format = tf
                break
            }
        }
        if (trackIndex < 0 || format == null) {
            extractor.release()
            throw IllegalArgumentException("No audio track found in $filePath")
        }
        extractor.selectTrack(trackIndex)

        val srcSr = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val srcCh = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

        val codec = MediaCodec.createDecoderByType(
            format.getString(MediaFormat.KEY_MIME)!!
        )
        codec.configure(format, null, null, 0)
        codec.start()

        val pcmOut = ByteArrayOutputStream()
        val info = MediaCodec.BufferInfo()
        var eos = false

        while (!eos) {
            // Feed input buffers.
            val inIdx = codec.dequeueInputBuffer(10_000)
            if (inIdx >= 0) {
                val inBuf = codec.getInputBuffer(inIdx)!!
                val read = extractor.readSampleData(inBuf, 0)
                if (read < 0) {
                    codec.queueInputBuffer(
                        inIdx, 0, 0, 0,
                        MediaCodec.BUFFER_FLAG_END_OF_STREAM
                    )
                } else {
                    codec.queueInputBuffer(
                        inIdx, 0, read,
                        extractor.sampleTime, 0
                    )
                    extractor.advance()
                }
            }

            // Drain output buffers.
            var outIdx = codec.dequeueOutputBuffer(info, 10_000)
            while (outIdx >= 0) {
                if (info.size > 0) {
                    val outBuf = codec.getOutputBuffer(outIdx)!!
                    val chunk = ByteArray(info.size)
                    outBuf.get(chunk)
                    pcmOut.write(chunk)
                }
                val endOfStream =
                    (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                codec.releaseOutputBuffer(outIdx, false)
                if (endOfStream) {
                    eos = true
                    break
                }
                outIdx = codec.dequeueOutputBuffer(info, 0)
            }
        }

        codec.stop()
        codec.release()
        extractor.release()

        // MediaCodec outputs 16-bit PCM. Down-mix to mono and resample
        // to targetSr if needed.
        val rawPcm = pcmOut.toByteArray()
        val srcSamples = ShortArray(rawPcm.size / 2)
        ByteBuffer.wrap(rawPcm).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
            .get(srcSamples)

        // Down-mix to mono.
        val mono: ShortArray = if (srcCh > 1) {
            val frames = srcSamples.size / srcCh
            ShortArray(frames) { i ->
                var sum = 0L
                for (c in 0 until srcCh) sum += srcSamples[i * srcCh + c]
                (sum / srcCh).toInt().toShort()
            }
        } else {
            srcSamples
        }

        // Simple linear resample to targetSr.
        val resampled: ShortArray = if (srcSr != targetSr) {
            val ratio = srcSr.toDouble() / targetSr
            val outLen = (mono.size / ratio).toInt()
            ShortArray(outLen) { i ->
                val srcPos = i * ratio
                val idx = srcPos.toInt().coerceAtMost(mono.size - 1)
                mono[idx]
            }
        } else {
            mono
        }

        // Build a WAV in memory.
        val dataSize = resampled.size * 2
        val wav = ByteBuffer.allocate(44 + dataSize)
            .order(ByteOrder.LITTLE_ENDIAN)
        // RIFF header
        wav.put("RIFF".toByteArray())
        wav.putInt(36 + dataSize)
        wav.put("WAVE".toByteArray())
        // fmt chunk
        wav.put("fmt ".toByteArray())
        wav.putInt(16)               // chunk size
        wav.putShort(1)              // PCM
        wav.putShort(1)              // mono
        wav.putInt(targetSr)
        wav.putInt(targetSr * 2)     // byte rate
        wav.putShort(2)              // block align
        wav.putShort(16)             // bits per sample
        // data chunk
        wav.put("data".toByteArray())
        wav.putInt(dataSize)
        for (s in resampled) wav.putShort(s)

        return wav.array()
    }
}
