import AVFoundation
import Foundation

/// **A clip made small enough to live in a shot list.**
///
/// Compiled into both apps, because the number that matters here — how many
/// bits a second a reference clip is worth — must be the same number on the
/// phone that shot it and the Mac that dragged it in, or the same film would
/// weigh twice as much depending on which door a clip came through.
///
/// ## Why not the preset
///
/// Both apps used `AVAssetExportPreset1280x720` until 2026-09-15. It makes a
/// 720p file, which was the point, at whatever bitrate Apple thinks 720p
/// deserves — measured on his real clips, seven to ten megabits a second. That
/// is a streaming service's number. A clip in a shot list is there to remember
/// a move, on a phone screen, and Call Her Back was carrying 390 MB of them
/// that 100 MB would have drawn identically. The preset offers no bitrate
/// dial, so this writes the file itself.
///
/// ## What it makes
///
/// - **720 on the short side, at most** — the same size as before. A clip
///   already smaller is not scaled up.
/// - **H.264, not HEVC.** HEVC would be a third smaller again, and the portal
///   plays these clips in whatever browser a director opens the film in; H.264
///   is the one every browser on every machine plays. The bitrate is where
///   the saving is, not the codec.
/// - **2.5 megabits a second**, average, with a two-second keyframe interval so
///   scrubbing lands where it was aimed.
/// - **AAC at 96 kbps**, stereo at most. A reference clip's sound is a slate
///   and some room tone.
/// - **The rotation baked in.** A clip shot upright carries its orientation
///   as a transform on the track, which some players honour and some do not;
///   the frames are turned on the way through so the file is upright however
///   it is read.
///
/// ## What it does not decide
///
/// Whether to keep the result. A clip that was already small and quiet can
/// come back *larger* from a fixed-bitrate pass, and the callers keep their
/// old rule: never store something bigger than it arrived.
enum ClipEncoder {
    /// Longest edge of the picture, the same limit the preset had.
    static let longestEdge: CGFloat = 1280
    /// Bits a second, on average.
    static let bitrate = 2_500_000
    /// Anything under this was not made by the old preset and is left alone
    /// by the pass that revisits stored clips — re-encoding a quiet file only
    /// loses quality for no room.
    static let loudEnough = 3_500_000

    struct Made {
        let url: URL
        let width: Int
        let height: Int
    }

    enum Trouble: Error {
        case unreadable
        case noPicture
        case writer(String)
    }

    /// The bitrate the file on disk was written at, in bits a second, from
    /// its own track. Nothing decoded.
    static func bitrate(of url: URL) async -> Int? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let rate = try? await track.load(.estimatedDataRate) else { return nil }
        return Int(rate)
    }

    /// Writes the small copy to `out`. Blocks the calling thread until the
    /// file is complete; the callers already run this off the window's own
    /// thread, and the writer does its work on queues of its own.
    static func shrink(_ source: URL, to out: URL) throws -> Made {
        let asset = AVURLAsset(url: source)
        guard let video = asset.tracks(withMediaType: .video).first else {
            throw Trouble.noPicture
        }
        let audio = asset.tracks(withMediaType: .audio).first

        // The picture's shape as it is meant to be seen, then scaled down to
        // fit — never up — and rounded to even numbers, which the encoder
        // requires.
        let natural = video.naturalSize
        let transform = video.preferredTransform
        let turned = natural.applying(transform)
        let shown = CGSize(width: abs(turned.width), height: abs(turned.height))
        guard shown.width > 0, shown.height > 0 else { throw Trouble.noPicture }
        let scale = min(1, longestEdge / max(shown.width, shown.height))
        let width = Int((shown.width * scale / 2).rounded()) * 2
        let height = Int((shown.height * scale / 2).rounded()) * 2

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        // ---- picture ----
        // A composition output turns and scales the frames on the way out,
        // so the rotation is in the pixels rather than in a flag.
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: width, height: height)
        let rate = video.nominalFrameRate > 0 ? video.nominalFrameRate : 30
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(rate.rounded()))
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: video)
        // Turn first, then move the turned picture back into the frame (a
        // 90° turn lands it at a negative x), then scale the lot.
        var placed = transform
        let box = CGRect(origin: .zero, size: natural).applying(transform)
        placed = placed.concatenating(CGAffineTransform(translationX: -box.minX, y: -box.minY))
        placed = placed.concatenating(CGAffineTransform(scaleX: CGFloat(width) / shown.width,
                                                        y: CGFloat(height) / shown.height))
        layer.setTransform(placed, at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]
        // **Say what colour the frames are, or the compositor guesses.** A
        // clip whose transfer tag is missing — his IMAX export of
        // 2026-09-19, `color_transfer=unknown`, primaries and matrix 709 —
        // came out of the composition green: the compositor picked a working
        // space that did not match the pixels and re-tagging the source
        // (gamma 2.4) did not help, because the guess is made here. Every
        // clip that reaches this is display video, so Rec.709 all three;
        // HDR sources are converted, which is what a 720p proxy wants.
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        let pictureOut = AVAssetReaderVideoCompositionOutput(
            videoTracks: [video],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        pictureOut.videoComposition = composition
        pictureOut.alwaysCopiesSampleData = false
        guard reader.canAdd(pictureOut) else { throw Trouble.unreadable }
        reader.add(pictureOut)

        let pictureIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            // …and write the same three into the file, so the proxy never
            // carries the source's blank tag on to the next reader.
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
                AVVideoAllowFrameReorderingKey: true,
                AVVideoExpectedSourceFrameRateKey: Int(rate.rounded()),
            ],
        ])
        pictureIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(pictureIn) else { throw Trouble.writer("no room for the picture") }
        writer.add(pictureIn)

        // ---- sound ----
        var soundOut: AVAssetReaderTrackOutput?
        var soundIn: AVAssetWriterInput?
        if let audio {
            let out = AVAssetReaderTrackOutput(track: audio, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
            ])
            out.alwaysCopiesSampleData = false
            if reader.canAdd(out) {
                reader.add(out)
                // Stereo at most; a channel layout is required above two and
                // a reference clip never earns it.
                var channels = 2
                var sampleRate = 48_000.0
                if let description = audio.formatDescriptions.first,
                   let basic = CMAudioFormatDescriptionGetStreamBasicDescription(
                       description as! CMAudioFormatDescription) {
                    channels = min(2, max(1, Int(basic.pointee.mChannelsPerFrame)))
                    if basic.pointee.mSampleRate > 0 { sampleRate = basic.pointee.mSampleRate }
                }
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: channels,
                    AVSampleRateKey: sampleRate,
                    AVEncoderBitRateKey: 96_000,
                ])
                input.expectsMediaDataInRealTime = false
                if writer.canAdd(input) {
                    writer.add(input)
                    soundOut = out
                    soundIn = input
                }
            }
        }

        // ---- pump ----
        guard reader.startReading() else {
            throw Trouble.writer(reader.error?.localizedDescription ?? "could not read the clip")
        }
        guard writer.startWriting() else {
            throw Trouble.writer(writer.error?.localizedDescription ?? "could not start the file")
        }
        writer.startSession(atSourceTime: .zero)

        let group = DispatchGroup()
        let lanes: [(AVAssetWriterInput, AVAssetReaderOutput)] = [(pictureIn, pictureOut)]
            + (soundIn.flatMap { input in soundOut.map { [(input, $0)] } } ?? [])
        for (index, (input, output)) in lanes.enumerated() {
            group.enter()
            let queue = DispatchQueue(label: "shotlister.clip.\(index)")
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if let sample = output.copyNextSampleBuffer() {
                        input.append(sample)
                    } else {
                        input.markAsFinished()
                        group.leave()
                        break
                    }
                }
            }
        }
        group.wait()

        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        reader.cancelReading()

        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: out)
            throw Trouble.writer(writer.error?.localizedDescription ?? "the file was not finished")
        }
        return Made(url: out, width: width, height: height)
    }
}
