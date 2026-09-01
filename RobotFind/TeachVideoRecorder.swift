import Foundation
import ARKit
import AVFoundation
import CoreMedia

enum TeachVideoRecorderError: LocalizedError {
    case writerUnavailable
    case cannotAddInput
    case writerFailed(String)
    case noFrames
    case invalidOutput
    case anchorVisibilityTimedOut
    case distanceGuidanceTimedOut

    var errorDescription: String? {
        switch self {
        case .writerUnavailable:
            return "The video writer could not be created."
        case .cannotAddInput:
            return "The video writer could not add its input."
        case .writerFailed(let message):
            return "Video recording failed: \(message)"
        case .noFrames:
            return "No valid AR frames were recorded."
        case .invalidOutput:
            return "The recorded video file is empty or invalid."
        case .anchorVisibilityTimedOut:
            return "The reference point was not visible long enough. Please try this view again."
        case .distanceGuidanceTimedOut:
            return "The phone did not reach the guided distance. Please try this view again."
        }
    }
}

struct FinalizedTeachVideo {
    let url: URL
    let duration: TimeInterval
    let fileSize: Int64
}

/// Writes ARFrame pixel buffers to one H.264 MP4 clip.
final class TeachVideoRecorder {
    private let fileManager = FileManager.default
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    private var firstTimestamp: CMTime?
    private var lastTimestamp: CMTime?
    private var frameCount = 0
    private var isFinishing = false
    private let minimumFrameInterval = CMTime(value: 1, timescale: 30)

    func startRecording(itemID: String, clipIndex: Int) throws {
        guard !isFinishing else { throw TeachVideoRecorderError.writerUnavailable }
        let url = try TeachCaptureStore.shared.clipURL(itemID: itemID, index: clipIndex)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        outputURL = url
        firstTimestamp = nil
        lastTimestamp = nil
        frameCount = 0
        writer = nil
        input = nil
        adaptor = nil
        print("[TeachVideo] recording clip=\(clipIndex)")
        print("[TeachVideo] recording started path=\(url.path)")
    }

    func append(frame: ARFrame) throws {
        guard !isFinishing, let outputURL else { return }
        let timestamp = CMTime(seconds: frame.timestamp, preferredTimescale: 600)

        if writer == nil {
            try createWriter(outputURL: outputURL, pixelBuffer: frame.capturedImage)
            firstTimestamp = timestamp
            writer?.startSession(atSourceTime: .zero)
        }

        guard let writer, let input, let adaptor, writer.status == .writing else {
            throw TeachVideoRecorderError.writerFailed(writer?.error?.localizedDescription ?? "writer is not writing")
        }
        guard input.isReadyForMoreMediaData else { return }
        if let lastTimestamp, timestamp - lastTimestamp < minimumFrameInterval { return }

        let relativeTime = timestamp - (firstTimestamp ?? timestamp)
        guard adaptor.append(frame.capturedImage, withPresentationTime: relativeTime) else {
            throw TeachVideoRecorderError.writerFailed(writer.error?.localizedDescription ?? "frame rejected")
        }
        self.lastTimestamp = timestamp
        frameCount += 1
    }

    func finish(completion: @escaping (Result<FinalizedTeachVideo, Error>) -> Void) {
        guard !isFinishing else { return }
        isFinishing = true

        guard let writer, let input, let outputURL else {
            isFinishing = false
            completion(.failure(TeachVideoRecorderError.noFrames))
            return
        }
        guard frameCount > 0 else {
            writer.cancelWriting()
            isFinishing = false
            completion(.failure(TeachVideoRecorderError.noFrames))
            return
        }

        input.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self else { return }
            self.isFinishing = false
            guard writer.status == .completed,
                  self.fileManager.fileExists(atPath: outputURL.path),
                  let attributes = try? self.fileManager.attributesOfItem(atPath: outputURL.path),
                  let size = (attributes[.size] as? NSNumber)?.int64Value,
                  size > 0 else {
                completion(.failure(TeachVideoRecorderError.writerFailed(writer.error?.localizedDescription ?? "writer did not complete")))
                return
            }

            let duration = AVURLAsset(url: outputURL).duration.seconds
            guard duration.isFinite, duration > 0 else {
                completion(.failure(TeachVideoRecorderError.invalidOutput))
                return
            }
            print("[TeachVideo] finalized \(outputURL.lastPathComponent)")
            print("[TeachVideo] duration=\(String(format: "%.2f", duration)) size=\(size)")
            completion(.success(FinalizedTeachVideo(url: outputURL, duration: duration, fileSize: size)))
        }
    }

    func cancel() {
        writer?.cancelWriting()
        if let outputURL, fileManager.fileExists(atPath: outputURL.path) {
            try? fileManager.removeItem(at: outputURL)
        }
        writer = nil
        input = nil
        adaptor = nil
        outputURL = nil
        firstTimestamp = nil
        lastTimestamp = nil
        frameCount = 0
        isFinishing = false
    }

    private func createWriter(outputURL: URL, pixelBuffer: CVPixelBuffer) throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 5_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        // ARKit's rear-camera buffer is landscape; this metadata presents it as portrait.
        input.transform = CGAffineTransform(rotationAngle: .pi / 2)
        guard writer.canAdd(input) else { throw TeachVideoRecorderError.cannotAddInput }
        writer.add(input)

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: CVPixelBufferGetPixelFormatType(pixelBuffer),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        self.writer = writer
        self.input = input
        self.adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        guard writer.startWriting() else {
            throw TeachVideoRecorderError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
    }
}
