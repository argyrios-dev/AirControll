@preconcurrency import AVFoundation
import AppKit
import Combine
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
  static let shared = AppModel()

  @Published private(set) var configuration: AppConfiguration
  @Published private(set) var recordingState: RecordingState = .idle
  @Published private(set) var lastRecognizedGestureName: String?
  @Published private(set) var statusMessage: String?
  @Published var selectedSection: SettingsSection = .general

  let permissionManager = PermissionManager()
  let stateStore = StateStore.shared

  private let cameraService = CameraCaptureService()
  private let matcher = DeterministicGestureMatcher()
  private let temporalGate = TemporalGestureGate()
  private let actionExecutor = ActionExecutor()
  private var recorder: GestureRecorder?
  private var saveTask: Task<Void, Never>?

  private init() {
    configuration = StateStore.shared.load()
    permissionManager.refresh()
    configuration.launchAtLogin = SMAppService.mainApp.status == .enabled
    if configuration.recognitionEnabled {
      setRecognitionEnabled(true)
    }
  }

  var recognitionEnabled: Bool { configuration.recognitionEnabled }
  var builtInsCalibrated: Bool { configuration.builtInsCalibrated }
  var applicationSupportPath: String { stateStore.applicationSupportURL.path }

  func gesture(id: UUID) -> GestureDefinition? {
    configuration.gestures.first { $0.id == id }
  }

  func addCustomGesture(named proposedName: String) {
    let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let uniqueName = makeUniqueGestureName(trimmed)
    configuration.gestures.append(
      GestureDefinition(
        id: UUID(),
        name: uniqueName,
        kind: .custom,
        action: .doNothing,
        template: nil
      ))
    persistSoon()
  }

  func deleteGesture(id: UUID) {
    guard let index = configuration.gestures.firstIndex(where: { $0.id == id }) else { return }
    if configuration.gestures[index].isBuiltIn {
      configuration.gestures[index].template = nil
    } else {
      configuration.gestures.remove(at: index)
    }
    if !configuration.builtInsCalibrated {
      setRecognitionEnabled(false)
    }
    if case .recording(let recordingID, _, _, _) = recordingState, recordingID == id {
      cancelRecording()
    }
    persistSoon()
  }

  func updateAction(for gestureID: UUID, action: GestureAction) {
    guard let index = configuration.gestures.firstIndex(where: { $0.id == gestureID }) else {
      return
    }
    configuration.gestures[index].action = action
    persistSoon()
  }

  func beginRecording(gestureID: UUID) {
    guard let gesture = gesture(id: gestureID) else { return }
    setRecognitionEnabled(false)
    permissionManager.refresh()
    guard permissionManager.cameraStatus == .authorized else {
      recordingState = .failed(
        gestureID: gestureID, message: "Camera permission is required before recording.")
      return
    }

    recorder = GestureRecorder(
      gestureID: gestureID,
      expectedHandCount: gesture.expectedHandCount,
      targetSampleCount: configuration.advanced.stableSampleTarget
    )
    recordingState = .preparing(gestureID: gestureID)
    startCamera()
    recordingState = .recording(
      gestureID: gestureID,
      accepted: 0,
      target: configuration.advanced.stableSampleTarget,
      rejected: 0
    )
  }

  func cancelRecording() {
    recorder = nil
    recordingState = .idle
    cameraService.stop()
  }

  func setRecognitionEnabled(_ enabled: Bool) {
    if !enabled {
      configuration.recognitionEnabled = false
      temporalGate.reset()
      cameraService.stop()
      persistSoon()
      NotificationCenter.default.post(name: .airControllRecognitionChanged, object: nil)
      return
    }

    configuration.recognitionEnabled = false
    guard configuration.builtInsCalibrated else {
      configuration.recognitionEnabled = false
      statusMessage =
        "Calibrate Closed Fist, Praying Hands, Thumbs Up and Thumbs Down before enabling recognition."
      NotificationCenter.default.post(name: .airControllRecognitionChanged, object: nil)
      return
    }

    permissionManager.refresh()
    if permissionManager.cameraStatus == .notDetermined {
      permissionManager.requestCamera()
      statusMessage = "Grant camera permission, then enable recognition again."
      return
    }
    guard permissionManager.cameraStatus == .authorized else {
      statusMessage = "Camera permission is required to enable recognition."
      return
    }

    configuration.recognitionEnabled = true
    temporalGate.reset()
    startCamera()
    persistSoon()
    NotificationCenter.default.post(name: .airControllRecognitionChanged, object: nil)
  }

  func toggleRecognition() {
    setRecognitionEnabled(!recognitionEnabled)
  }

  func setRecognitionRunMode(_ mode: RecognitionRunMode) {
    var advanced = configuration.advanced
    advanced.recognitionRunMode = mode
    setAdvanced(advanced)
  }

  func setHandUsageMode(_ mode: HandUsageMode) {
    var advanced = configuration.advanced
    advanced.handUsageMode = mode
    temporalGate.reset()
    setAdvanced(advanced)
  }

  func setAdvanced(_ advanced: AdvancedSettings) {
    var sanitized = advanced
    sanitized.sanitize()
    configuration.advanced = sanitized
    if recognitionEnabled || recorder != nil {
      cameraService.stop()
      startCamera()
    }
    persistSoon()
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      configuration.launchAtLogin = SMAppService.mainApp.status == .enabled
      if enabled && !configuration.launchAtLogin {
        statusMessage = "Launch at Login requires approval in System Settings."
      }
      persistSoon()
    } catch {
      statusMessage = "Launch at Login could not be changed: \(error.localizedDescription)"
    }
  }

  func chooseApplication(for gestureID: UUID) {
    let panel = NSOpenPanel()
    panel.title = "Choose Application"
    panel.prompt = "Choose"
    panel.allowedContentTypes = [.application]
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      let data = try url.bookmarkData(
        options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
        includingResourceValuesForKeys: [.nameKey],
        relativeTo: nil
      )
      let bundleIdentifier = Bundle(url: url)?.bundleIdentifier
      let bookmark = ApplicationBookmark(
        bookmarkData: data,
        displayName: url.deletingPathExtension().lastPathComponent,
        bundleIdentifier: bundleIdentifier
      )
      updateAction(for: gestureID, action: .openApplication(bookmark))
    } catch {
      statusMessage = "The application bookmark could not be saved: \(error.localizedDescription)"
    }
  }

  func openApplicationSupportFolder() {
    do {
      try FileManager.default.createDirectory(
        at: stateStore.applicationSupportURL, withIntermediateDirectories: true)
      NSWorkspace.shared.open(stateStore.applicationSupportURL)
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  func deleteAllLearnedData() {
    saveTask?.cancel()
    configuration.recognitionEnabled = false
    temporalGate.reset()
    recorder = nil
    cameraService.releaseCamera()
    do {
      configuration = try stateStore.deleteLearnedData()
      recordingState = .idle
      lastRecognizedGestureName = nil
      statusMessage = "Learned gesture data was deleted."
      NotificationCenter.default.post(name: .airControllRecognitionChanged, object: nil)
    } catch {
      statusMessage = "Learned data could not be deleted: \(error.localizedDescription)"
    }
  }

  func clearStatusMessage() { statusMessage = nil }

  func shutdown() {
    saveTask?.cancel()
    try? stateStore.saveImmediately(configuration)
    cameraService.releaseCamera()
  }

  private func startCamera() {
    cameraService.start(
      framesPerSecond: configuration.advanced.framesPerSecond,
      minimumPointConfidence: configuration.advanced.minimumPointConfidence,
      features: { [weak self] vector in
        Task { @MainActor in self?.consume(vector) }
      },
      onError: { [weak self] error in
        Task { @MainActor in self?.handleCameraError(error) }
      }
    )
  }

  private func handleCameraError(_ error: Error) {
    statusMessage = error.localizedDescription
    switch recordingState {
    case .preparing(let gestureID), .recording(let gestureID, _, _, _):
      recorder = nil
      recordingState = .failed(gestureID: gestureID, message: error.localizedDescription)
      cameraService.stop()
    default:
      if recognitionEnabled { setRecognitionEnabled(false) }
    }
  }

  private func consume(_ vector: ExtractedFeatureVector?) {
    guard let vector else {
      if var activeRecorder = recorder {
        activeRecorder.rejectOne()
        recorder = activeRecorder
        recordingState = .recording(
          gestureID: activeRecorder.gestureID,
          accepted: activeRecorder.samples.count,
          target: activeRecorder.targetSampleCount,
          rejected: activeRecorder.rejectedCount
        )
      } else if recognitionEnabled {
        _ = temporalGate.consume(
          nil,
          requiredFrames: configuration.advanced.temporalStabilityFrames,
          cooldown: configuration.advanced.cooldownSeconds
        )
      }
      return
    }

    if var activeRecorder = recorder {
      if vector.handCount == 1,
        !configuration.advanced.handUsageMode.accepts(vector.singleHandSide)
      {
        activeRecorder.rejectOne()
        recorder = activeRecorder
        recordingState = .recording(
          gestureID: activeRecorder.gestureID,
          accepted: activeRecorder.samples.count,
          target: activeRecorder.targetSampleCount,
          rejected: activeRecorder.rejectedCount
        )
        return
      }

      let accepted = activeRecorder.accept(vector)
      recorder = activeRecorder
      recordingState = .recording(
        gestureID: activeRecorder.gestureID,
        accepted: activeRecorder.samples.count,
        target: activeRecorder.targetSampleCount,
        rejected: activeRecorder.rejectedCount
      )
      if accepted && activeRecorder.isComplete {
        finishRecording(activeRecorder)
      }
      return
    }

    guard recognitionEnabled else { return }
    let match = matcher.bestMatch(
      vector: vector,
      gestures: configuration.gestures,
      handUsageMode: configuration.advanced.handUsageMode
    )
    if let triggeredID = temporalGate.consume(
      match,
      requiredFrames: configuration.advanced.temporalStabilityFrames,
      cooldown: configuration.advanced.cooldownSeconds
    ), let gesture = gesture(id: triggeredID) {
      lastRecognizedGestureName = gesture.name
      let shouldReturnToIdle = configuration.advanced.recognitionRunMode == .oneTime
      do {
        try actionExecutor.execute(gesture.action)
      } catch {
        statusMessage = error.localizedDescription
      }
      if shouldReturnToIdle {
        setRecognitionEnabled(false)
      }
    }
  }

  private func finishRecording(_ completedRecorder: GestureRecorder) {
    do {
      let template = try completedRecorder.makeTemplate()
      guard
        let index = configuration.gestures.firstIndex(where: {
          $0.id == completedRecorder.gestureID
        })
      else { return }
      configuration.gestures[index].template = template
      recorder = nil
      recordingState = .completed(gestureID: completedRecorder.gestureID)
      cameraService.stop()
      persistSoon()
    } catch {
      recorder = nil
      recordingState = .failed(
        gestureID: completedRecorder.gestureID, message: error.localizedDescription)
      cameraService.stop()
    }
  }

  private func makeUniqueGestureName(_ base: String) -> String {
    let names = Set(configuration.gestures.map { $0.name.lowercased() })
    if !names.contains(base.lowercased()) { return base }
    var number = 2
    while names.contains("\(base) \(number)".lowercased()) { number += 1 }
    return "\(base) \(number)"
  }

  private func persistSoon() {
    saveTask?.cancel()
    let snapshot = configuration
    saveTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 250_000_000)
      guard !Task.isCancelled, let self else { return }
      self.stateStore.save(snapshot) { [weak self] result in
        if case .failure(let error) = result {
          self?.statusMessage = "Settings could not be saved: \(error.localizedDescription)"
        }
      }
    }
  }
}
