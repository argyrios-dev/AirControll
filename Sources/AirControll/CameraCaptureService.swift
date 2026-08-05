@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
@preconcurrency import Vision

final class CameraCaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
  @unchecked Sendable
{
  typealias FeatureHandler = @Sendable (ExtractedFeatureVector?) -> Void
  typealias ErrorHandler = @Sendable (Error) -> Void

  private final class PixelBufferBox: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer

    init(_ pixelBuffer: CVPixelBuffer) {
      self.pixelBuffer = pixelBuffer
    }
  }

  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(
    label: "com.aircontroll.camera.session", qos: .userInitiated)
  private let videoQueue = DispatchQueue(
    label: "com.aircontroll.camera.frames", qos: .userInitiated)
  private let processingQueue = DispatchQueue(
    label: "com.aircontroll.camera.vision", qos: .userInitiated)
  private let stateLock = NSLock()

  private var configured = false
  private var acceptingFrames = false
  private var processingFrame = false
  private var generation: UInt64 = 0
  private var lastProcessedTime: TimeInterval = 0
  private var desiredFramesPerSecond = 12
  private var minimumPointConfidence = 0.35
  private let featureExtractor = HandPoseFeatureExtractor()
  private var featureHandler: FeatureHandler?
  private var errorHandler: ErrorHandler?

  func start(
    framesPerSecond: Int,
    minimumPointConfidence: Double,
    features: @escaping FeatureHandler,
    onError: @escaping ErrorHandler
  ) {
    let startGeneration: UInt64 = stateLock.withLock {
      desiredFramesPerSecond = min(15, max(10, framesPerSecond))
      self.minimumPointConfidence = min(0.75, max(0.2, minimumPointConfidence))
      lastProcessedTime = 0
      generation &+= 1
      acceptingFrames = true
      featureHandler = features
      errorHandler = onError
      return generation
    }

    sessionQueue.async { [weak self] in
      guard let self else { return }
      do {
        try self.configureIfNeeded()
        guard !self.session.isRunning else { return }
        self.session.startRunning()
      } catch {
        let isCurrent = self.stateLock.withLock {
          guard self.generation == startGeneration else { return false }
          self.acceptingFrames = false
          return true
        }
        if isCurrent { self.deliver(error: error) }
      }
    }
  }

  func stop() {
    stateLock.withLock {
      acceptingFrames = false
      generation &+= 1
      featureHandler = nil
      errorHandler = nil
    }

    sessionQueue.async { [weak self] in
      self?.tearDownSession()
    }
  }

  func releaseCamera() {
    stateLock.withLock {
      acceptingFrames = false
      generation &+= 1
      featureHandler = nil
      errorHandler = nil
    }

    sessionQueue.sync { [self] in
      tearDownSession()
    }
  }

  private func tearDownSession() {
    if session.isRunning { session.stopRunning() }
    session.beginConfiguration()
    for output in session.outputs {
      if let videoOutput = output as? AVCaptureVideoDataOutput {
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
      }
      session.removeOutput(output)
    }
    for input in session.inputs { session.removeInput(input) }
    session.commitConfiguration()
    configured = false
  }

  private func configureIfNeeded() throws {
    guard !configured else { return }
    guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
      throw CameraError.permissionNotGranted
    }
    guard
      let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        ?? AVCaptureDevice.default(for: .video)
    else { throw CameraError.noCamera }

    let input = try AVCaptureDeviceInput(device: device)
    let output = AVCaptureVideoDataOutput()
    output.alwaysDiscardsLateVideoFrames = true
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
    ]
    output.setSampleBufferDelegate(self, queue: videoQueue)

    session.beginConfiguration()
    session.sessionPreset = .medium
    guard session.canAddInput(input), session.canAddOutput(output) else {
      session.commitConfiguration()
      throw CameraError.configurationFailed
    }
    session.addInput(input)
    session.addOutput(output)
    session.commitConfiguration()
    configured = true
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    let now =
      presentationTime.isValid
      ? CMTimeGetSeconds(presentationTime)
      : Date().timeIntervalSinceReferenceDate
    let work: (generation: UInt64, confidence: Double)? = stateLock.withLock {
      let minimumInterval = 1.0 / Double(desiredFramesPerSecond)
      guard acceptingFrames, !processingFrame, now - lastProcessedTime >= minimumInterval else {
        return nil
      }
      processingFrame = true
      lastProcessedTime = now
      return (generation, minimumPointConfidence)
    }
    guard let work else { return }

    let box = PixelBufferBox(pixelBuffer)
    processingQueue.async { [weak self, box] in
      autoreleasepool {
        self?.process(
          box.pixelBuffer,
          generation: work.generation,
          minimumConfidence: work.confidence
        )
      }
    }
  }

  private func process(
    _ pixelBuffer: CVPixelBuffer,
    generation workGeneration: UInt64,
    minimumConfidence: Double
  ) {
    defer {
      stateLock.withLock { processingFrame = false }
    }

    let request = VNDetectHumanHandPoseRequest()
    request.maximumHandCount = 2
    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

    do {
      try handler.perform([request])
      let observations = request.results ?? []
      let callback: FeatureHandler? = stateLock.withLock {
        guard acceptingFrames, generation == workGeneration else { return nil }
        return featureHandler
      }
      guard let callback else { return }
      if observations.isEmpty {
        callback(nil)
      } else {
        let vector = try? featureExtractor.extract(
          from: observations,
          minimumConfidence: minimumConfidence
        )
        callback(vector)
      }
    } catch {
      let shouldDeliver = stateLock.withLock {
        acceptingFrames && generation == workGeneration
      }
      if shouldDeliver { deliver(error: error) }
    }
  }

  private func deliver(error: Error) {
    let callback = stateLock.withLock { errorHandler }
    callback?(error)
  }

  deinit {
    if session.isRunning { session.stopRunning() }
  }
}

enum CameraError: LocalizedError {
  case permissionNotGranted
  case noCamera
  case configurationFailed

  var errorDescription: String? {
    switch self {
    case .permissionNotGranted: "Camera permission has not been granted."
    case .noCamera: "No camera is available."
    case .configurationFailed: "The camera capture session could not be configured."
    }
  }
}
