// SystemAudioCapture — macOS native side for PLAN §5.1.1.
//
// Uses ScreenCaptureKit (macOS 12.3+) to capture system audio
// without requiring a virtual audio device like BlackHole. The
// user must grant Screen Recording permission once in System
// Settings → Privacy & Security → Screen Recording.
//
// Wire protocol:
//   MethodChannel `crisperweaver/system_audio_capture` — control
//     • isSupported() → bool — runtime probe (false on macOS 11.x)
//     • start() → bool — fires the SCStream, streams PCM on the
//       EventChannel sink, returns true on success
//     • stop() → null — clean teardown
//   EventChannel `crisperweaver/system_audio_capture/stream` —
//     Uint8List (Float32 16 kHz mono PCM) frames
//
// The conversion pipeline:
//   SCStream audio output → CMSampleBuffer (typically 48 kHz
//   stereo Float32) → AVAudioConverter → 16 kHz mono Float32 →
//   EventChannel
//
// Permission story: SCStream startCapture() throws when the user
// hasn't granted Screen Recording. We map that to
// `permission_denied` so the Dart side surfaces a localized
// "open System Settings" hint.

import Cocoa
import FlutterMacOS
import AVFoundation
import CoreGraphics
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

/// Channel names — keep in sync with `system_audio_capture_service.dart`.
private let kControlChannel = "crisperweaver/system_audio_capture"
private let kStreamChannel = "crisperweaver/system_audio_capture/stream"

/// Target output format for the transcription pipeline. 16 kHz mono
/// Float32 — every CrispASR backend expects exactly this.
private let kTargetSampleRate: Double = 16000
private let kTargetChannels: AVAudioChannelCount = 1

@available(macOS 13.0, *)
final class SystemAudioCaptureHandler: NSObject, SCStreamDelegate,
    SCStreamOutput, FlutterStreamHandler {

    private var stream: SCStream?
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var sink: FlutterEventSink?
    /// Serializes start / stop / event-sink mutations so a fast
    /// stop() right after start() doesn't race the SCStream callback.
    private let lock = NSRecursiveLock()

    /// Lazy — created once we know what AudioStreamBasicDescription
    /// the SCStream emits (typically 48 kHz stereo Float32).
    private lazy var targetFormat: AVAudioFormat? = {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: kTargetSampleRate,
            channels: kTargetChannels,
            interleaved: false)
    }()

    // ---------- FlutterStreamHandler ----------

    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        lock.lock(); defer { lock.unlock() }
        sink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        lock.lock(); defer { lock.unlock() }
        sink = nil
        return nil
    }

    // ---------- Control entrypoints ----------

    /// Begin capture. Returns true on success; throws
    /// `permission_denied` / `unsupported` via the completion
    /// closure on failure.
    func start(completion: @escaping (Result<Bool, NSError>) -> Void) {
        Task { @MainActor in
            do {
                // Ask explicitly before enumerating shareable content. A
                // missing or stale grant is not proof the user clicked Deny.
                if !CGPreflightScreenCaptureAccess() && !CGRequestScreenCaptureAccess() {
                    completion(.failure(NSError(
                        domain: "SystemAudioCapture",
                        code: 2,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "System audio capture is not authorized for this app. Open System Settings → Privacy & Security → Screen & System Audio Recording, enable CrisperWeaver, then quit and reopen the app. If several copies are listed, select this local build.",
                            "code": "permission_denied",
                        ])))
                    return
                }
                // 1. Pick a shareable-content target. Audio capture
                // is keyed off a display filter even though we don't
                // care about pixels — SCContentFilter requires SOME
                // visual surface as the audio key.
                let content = try await SCShareableContent
                    .excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    completion(.failure(NSError(
                        domain: "SystemAudioCapture",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey:
                            "No displays available"])))
                    return
                }
                let filter = SCContentFilter(
                    display: display, excludingWindows: [])

                let config = SCStreamConfiguration()
                config.capturesAudio = true
                // Avoid feedback loops — don't capture our own
                // playback. Useful when the user is previewing a
                // transcript via the in-app player.
                config.excludesCurrentProcessAudio = true
                // Tiny video config — we have to set SOMETHING per
                // the framework rules even though we throw away the
                // video. 64×64 @ 1 fps is essentially free.
                config.width = 64
                config.height = 64
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                // Audio: ScreenCaptureKit emits at the device's
                // native rate (typically 48 kHz). We let it.
                config.sampleRate = 48000
                config.channelCount = 2

                let s = SCStream(filter: filter, configuration: config,
                                 delegate: self)
                try s.addStreamOutput(self, type: .audio,
                                      sampleHandlerQueue: nil)
                try await s.startCapture()
                // Stash the stream via a sync helper — calling
                // `lock.lock()` / `lock.unlock()` directly from this
                // async closure is unavailable under Swift 6 (the
                // suspension point between them risks deadlock).
                self.assignStream(s)
                completion(.success(true))
            } catch {
                let nsErr = error as NSError
                // SCStream's permission errors come out as code -3801
                // ("Authorization required") in the SCStreamErrorDomain.
                let code: String
                if nsErr.code == -3801
                    || nsErr.localizedDescription
                        .lowercased().contains("permission") {
                    code = "permission_denied"
                } else {
                    code = "start_failed"
                }
                completion(.failure(NSError(
                    domain: "SystemAudioCapture",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: code == "permission_denied"
                            ? "macOS has not authorized system audio capture for this app. Enable it in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen the app."
                            : nsErr.localizedDescription,
                        "code": code,
                    ])))
            }
        }
    }

    /// Sync helper used by the async start() closure — see comment
    /// at the call site for why we don't inline lock()/unlock() there.
    private func assignStream(_ s: SCStream) {
        lock.lock()
        stream = s
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let s = stream
        stream = nil
        converter = nil
        sourceFormat = nil
        lock.unlock()
        guard let s = s else { return }
        Task {
            do {
                try await s.stopCapture()
            } catch {
                // Best-effort; the stream is unreachable anyway after
                // teardown.
            }
        }
    }

    // ---------- SCStreamOutput ----------

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(
                  formatDesc)?.pointee else { return }

        // First buffer: build the AVAudioConverter for the SCStream's
        // actual native format → 16 kHz mono Float32. The buffer's
        // ASBD tells us the source layout (sample rate / channels /
        // interleaving) — we don't hardcode it.
        lock.lock()
        if converter == nil {
            var asbdLocal = asbd
            guard let src = AVAudioFormat(streamDescription: &asbdLocal),
                  let dst = targetFormat else {
                lock.unlock(); return
            }
            sourceFormat = src
            converter = AVAudioConverter(from: src, to: dst)
        }
        let conv = converter
        let src = sourceFormat
        let sink = self.sink
        lock.unlock()
        guard let conv = conv, let src = src, let sink = sink,
              let dst = targetFormat else { return }

        // Convert the CMSampleBuffer's data into an AVAudioPCMBuffer
        // the converter can chew on. We can't put the bytes directly
        // into a Float32 AVAudioPCMBuffer when the source is
        // interleaved or at a different rate — AVAudioConverter
        // handles both.
        guard let pcm = sampleBufferToPCMBuffer(sampleBuffer, format: src)
        else { return }

        // Output capacity: ceil(inputFrames * dstRate / srcRate) + 1
        // for safety on resampler border conditions.
        let outFrameCap = AVAudioFrameCount(
            ceil(Double(pcm.frameLength) * dst.sampleRate
                 / src.sampleRate)) + 16
        guard let outBuf = AVAudioPCMBuffer(
            pcmFormat: dst, frameCapacity: outFrameCap) else { return }

        var err: NSError?
        var supplied = false
        let status = conv.convert(to: outBuf, error: &err) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return pcm
        }
        if status == .error || outBuf.frameLength == 0 { return }

        // Float32 mono → Uint8List for the wire (zero-copy on the
        // Dart side via Float32List.view).
        guard let ch = outBuf.floatChannelData?[0] else { return }
        let byteCount = Int(outBuf.frameLength) * MemoryLayout<Float>.size
        let data = Data(bytes: ch, count: byteCount)
        DispatchQueue.main.async {
            sink(FlutterStandardTypedData(bytes: data))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let sink = self.sink
        DispatchQueue.main.async {
            sink?(FlutterError(
                code: "stream_stopped",
                message: error.localizedDescription,
                details: nil))
        }
    }

    private func sampleBufferToPCMBuffer(
        _ sampleBuffer: CMSampleBuffer,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0,
              let blockBuf = CMSampleBufferGetDataBuffer(sampleBuffer)
        else { return nil }
        let frames = AVAudioFrameCount(numSamples)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format,
                                          frameCapacity: frames)
        else { return nil }
        pcm.frameLength = frames

        var lengthOut = 0
        var ptrOut: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuf, atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &lengthOut,
            dataPointerOut: &ptrOut)
        guard status == kCMBlockBufferNoErr, let ptrOut = ptrOut else {
            return nil
        }

        // For interleaved float32 source (typical from SCStream),
        // the bytes are already laid out the way an interleaved
        // AVAudioPCMBuffer expects.
        if format.isInterleaved {
            // memcpy into the first interleaved channel slot
            if let f = pcm.floatChannelData?[0] {
                memcpy(f, ptrOut, lengthOut)
            } else if let i = pcm.int16ChannelData?[0] {
                memcpy(i, ptrOut, lengthOut)
            }
        } else {
            // Non-interleaved: rare from SCStream but support it.
            if let f = pcm.floatChannelData?[0] {
                memcpy(f, ptrOut, lengthOut)
            }
        }
        return pcm
    }
}

/// Plugin entry — called from MainFlutterWindow's awakeFromNib so
/// the channels are live by the time Flutter side first invokes
/// them.
func registerSystemAudioCapture(messenger: FlutterBinaryMessenger) {
    let control = FlutterMethodChannel(
        name: kControlChannel, binaryMessenger: messenger)
    let stream = FlutterEventChannel(
        name: kStreamChannel, binaryMessenger: messenger)

    // Bind once; reuse across start/stop cycles.
    var handler: AnyObject?

    control.setMethodCallHandler { call, result in
        switch call.method {
        case "isSupported":
            if #available(macOS 13.0, *) {
                result(true)
            } else {
                result(false)
            }
        case "start":
            guard #available(macOS 13.0, *) else {
                result(FlutterError(
                    code: "os_too_old",
                    message:
                        "ScreenCaptureKit audio capture requires macOS 13 or later",
                    details: nil))
                return
            }
            // Build or reuse the handler.
            let h: SystemAudioCaptureHandler
            if let existing = handler as? SystemAudioCaptureHandler {
                h = existing
            } else {
                h = SystemAudioCaptureHandler()
                handler = h
                stream.setStreamHandler(h)
            }
            h.start { res in
                switch res {
                case .success(let ok):
                    DispatchQueue.main.async { result(ok) }
                case .failure(let err):
                    let code = err.userInfo["code"] as? String ?? "start_failed"
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: code,
                            message: err.localizedDescription,
                            details: nil))
                    }
                }
            }
        case "stop":
            if #available(macOS 13.0, *) {
                (handler as? SystemAudioCaptureHandler)?.stop()
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
