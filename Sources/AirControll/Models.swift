import Foundation

let airControllVersion = "0.1.5"
let airControllBundleIdentifier = "com.aircontroll.app"

enum SettingsSection: String, CaseIterable, Identifiable, Hashable, Sendable {
  case general = "General"
  case gestures = "Gestures"
  case actions = "Actions"
  case privacy = "Privacy"
  case advanced = "Advanced"
  case about = "About"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .general: "gearshape"
    case .gestures: "hand.raised"
    case .actions: "bolt"
    case .privacy: "lock.shield"
    case .advanced: "slider.horizontal.3"
    case .about: "info.circle"
    }
  }
}

enum RecognitionRunMode: String, CaseIterable, Codable, Identifiable, Sendable {
  case continuous
  case oneTime

  var id: String { rawValue }

  var title: String {
    switch self {
    case .continuous: "Continuous"
    case .oneTime: "One Time"
    }
  }

  var explanation: String {
    switch self {
    case .continuous:
      "Keep recognition and the camera active after an action."
    case .oneTime:
      "Execute one action, return to idle and release the camera."
    }
  }
}

enum HandUsageMode: String, CaseIterable, Codable, Identifiable, Sendable {
  case left
  case right
  case both

  var id: String { rawValue }

  var title: String {
    switch self {
    case .left: "Left"
    case .right: "Right"
    case .both: "Both"
    }
  }

  var systemImage: String {
    switch self {
    case .left: "hand.raised.fill"
    case .right: "hand.raised.fill"
    case .both: "hands.sparkles.fill"
    }
  }

  var explanation: String {
    switch self {
    case .left:
      "Accept one-handed gestures only from the left hand. Existing right-hand recordings are mirrored automatically."
    case .right:
      "Accept one-handed gestures only from the right hand. Existing left-hand recordings are mirrored automatically."
    case .both:
      "Accept one-handed gestures from either hand without recording a second gesture."
    }
  }

  func accepts(_ side: HandSide?) -> Bool {
    guard let side else { return self == .both }
    switch self {
    case .left: return side == .left
    case .right: return side == .right
    case .both: return true
    }
  }
}

enum HandSide: String, Codable, Sendable {
  case left
  case right
}

enum BuiltInGesture: String, CaseIterable, Codable, Identifiable, Sendable {
  case closedFist = "Closed Fist"
  case prayingHands = "Praying Hands"
  case thumbsUp = "Thumbs Up"
  case thumbsDown = "Thumbs Down"

  var id: String { rawValue }

  var expectedHandCount: Int {
    self == .prayingHands ? 2 : 1
  }
}

enum GestureKind: Codable, Equatable, Sendable {
  case builtIn(BuiltInGesture)
  case custom

  private enum CodingKeys: String, CodingKey { case type, builtIn }
  private enum KindValue: String, Codable { case builtIn, custom }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(KindValue.self, forKey: .type) {
    case .builtIn:
      self = .builtIn(try container.decode(BuiltInGesture.self, forKey: .builtIn))
    case .custom:
      self = .custom
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .builtIn(let gesture):
      try container.encode(KindValue.builtIn, forKey: .type)
      try container.encode(gesture, forKey: .builtIn)
    case .custom:
      try container.encode(KindValue.custom, forKey: .type)
    }
  }
}

struct KeyboardShortcut: Codable, Equatable, Hashable, Sendable {
  var keyCode: UInt16
  var modifierFlagsRawValue: UInt64
  var displayText: String
  var isModifierOnly: Bool

  init(
    keyCode: UInt16,
    modifierFlagsRawValue: UInt64,
    displayText: String,
    isModifierOnly: Bool = false
  ) {
    self.keyCode = keyCode
    self.modifierFlagsRawValue = modifierFlagsRawValue
    self.displayText = displayText
    self.isModifierOnly = isModifierOnly
  }

  private enum CodingKeys: String, CodingKey {
    case keyCode
    case modifierFlagsRawValue
    case displayText
    case isModifierOnly
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    keyCode = try container.decode(UInt16.self, forKey: .keyCode)
    modifierFlagsRawValue = try container.decode(UInt64.self, forKey: .modifierFlagsRawValue)
    displayText = try container.decode(String.self, forKey: .displayText)
    isModifierOnly = try container.decodeIfPresent(Bool.self, forKey: .isModifierOnly) ?? false
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(keyCode, forKey: .keyCode)
    try container.encode(modifierFlagsRawValue, forKey: .modifierFlagsRawValue)
    try container.encode(displayText, forKey: .displayText)
    try container.encode(isModifierOnly, forKey: .isModifierOnly)
  }
}

struct ApplicationBookmark: Codable, Equatable, Hashable, Sendable {
  var bookmarkData: Data
  var displayName: String
  var bundleIdentifier: String?
}

enum GestureAction: Codable, Equatable, Hashable, Sendable {
  case playPause
  case nextTrack
  case previousTrack
  case volumeUp
  case volumeDown
  case mute
  case brightnessUp
  case brightnessDown
  case missionControl
  case showDesktop
  case lockScreen
  case screenshot
  case openApplication(ApplicationBookmark?)
  case keyboardShortcut(KeyboardShortcut?)
  case doNothing

  var title: String {
    switch self {
    case .playPause: "Play/Pause"
    case .nextTrack: "Next Track"
    case .previousTrack: "Previous Track"
    case .volumeUp: "Volume Up"
    case .volumeDown: "Volume Down"
    case .mute: "Mute"
    case .brightnessUp: "Brightness Up"
    case .brightnessDown: "Brightness Down"
    case .missionControl: "Mission Control"
    case .showDesktop: "Show Desktop"
    case .lockScreen: "Lock Screen"
    case .screenshot: "Screenshot"
    case .openApplication: "Open Application"
    case .keyboardShortcut: "Keyboard Shortcut"
    case .doNothing: "Do Nothing"
    }
  }

  var requiresAccessibility: Bool {
    switch self {
    case .brightnessUp, .brightnessDown, .missionControl, .showDesktop,
      .lockScreen, .screenshot, .keyboardShortcut:
      true
    default:
      false
    }
  }
}

enum ActionKind: String, CaseIterable, Identifiable, Sendable {
  case playPause = "Play/Pause"
  case nextTrack = "Next Track"
  case previousTrack = "Previous Track"
  case volumeUp = "Volume Up"
  case volumeDown = "Volume Down"
  case mute = "Mute"
  case brightnessUp = "Brightness Up"
  case brightnessDown = "Brightness Down"
  case missionControl = "Mission Control"
  case showDesktop = "Show Desktop"
  case lockScreen = "Lock Screen"
  case screenshot = "Screenshot"
  case openApplication = "Open Application"
  case keyboardShortcut = "Keyboard Shortcut"
  case doNothing = "Do Nothing"

  var id: String { rawValue }

  init(action: GestureAction) {
    switch action {
    case .playPause: self = .playPause
    case .nextTrack: self = .nextTrack
    case .previousTrack: self = .previousTrack
    case .volumeUp: self = .volumeUp
    case .volumeDown: self = .volumeDown
    case .mute: self = .mute
    case .brightnessUp: self = .brightnessUp
    case .brightnessDown: self = .brightnessDown
    case .missionControl: self = .missionControl
    case .showDesktop: self = .showDesktop
    case .lockScreen: self = .lockScreen
    case .screenshot: self = .screenshot
    case .openApplication: self = .openApplication
    case .keyboardShortcut: self = .keyboardShortcut
    case .doNothing: self = .doNothing
    }
  }

  func makeAction(bookmark: ApplicationBookmark?, shortcut: KeyboardShortcut?) -> GestureAction {
    switch self {
    case .playPause: .playPause
    case .nextTrack: .nextTrack
    case .previousTrack: .previousTrack
    case .volumeUp: .volumeUp
    case .volumeDown: .volumeDown
    case .mute: .mute
    case .brightnessUp: .brightnessUp
    case .brightnessDown: .brightnessDown
    case .missionControl: .missionControl
    case .showDesktop: .showDesktop
    case .lockScreen: .lockScreen
    case .screenshot: .screenshot
    case .openApplication: .openApplication(bookmark)
    case .keyboardShortcut: .keyboardShortcut(shortcut)
    case .doNothing: .doNothing
    }
  }
}

struct GestureTemplate: Codable, Equatable, Sendable {
  var featureNames: [String]
  var mean: [Double]
  var variance: [Double]
  var weights: [Double]
  var threshold: Double
  var sampleCount: Int
  var recordingDate: Date
  var expectedHandCount: Int

  var isValid: Bool {
    let count = featureNames.count
    guard count > 0,
      mean.count == count,
      variance.count == count,
      weights.count == count,
      threshold.isFinite,
      threshold > 0,
      sampleCount >= 24,
      (1...2).contains(expectedHandCount)
    else { return false }

    return mean.allSatisfy(\.isFinite)
      && variance.allSatisfy { $0.isFinite && $0 > 0 }
      && weights.allSatisfy { $0.isFinite && $0 > 0 }
  }
}

struct GestureDefinition: Codable, Identifiable, Equatable, Sendable {
  var id: UUID
  var name: String
  var kind: GestureKind
  var action: GestureAction
  var template: GestureTemplate?

  var isCalibrated: Bool { template != nil }
  var isBuiltIn: Bool {
    if case .builtIn = kind { return true }
    return false
  }

  var expectedHandCount: Int? {
    if case .builtIn(let builtIn) = kind { return builtIn.expectedHandCount }
    return nil
  }
}

struct AdvancedSettings: Codable, Equatable, Sendable {
  var framesPerSecond: Int
  var minimumPointConfidence: Double
  var stableSampleTarget: Int
  var temporalStabilityFrames: Int
  var cooldownSeconds: Double
  var recognitionRunMode: RecognitionRunMode
  var handUsageMode: HandUsageMode

  init(
    framesPerSecond: Int = 12,
    minimumPointConfidence: Double = 0.35,
    stableSampleTarget: Int = 36,
    temporalStabilityFrames: Int = 5,
    cooldownSeconds: Double = 1.5,
    recognitionRunMode: RecognitionRunMode = .continuous,
    handUsageMode: HandUsageMode = .both
  ) {
    self.framesPerSecond = framesPerSecond
    self.minimumPointConfidence = minimumPointConfidence
    self.stableSampleTarget = stableSampleTarget
    self.temporalStabilityFrames = temporalStabilityFrames
    self.cooldownSeconds = cooldownSeconds
    self.recognitionRunMode = recognitionRunMode
    self.handUsageMode = handUsageMode
    sanitize()
  }

  private enum CodingKeys: String, CodingKey {
    case framesPerSecond
    case minimumPointConfidence
    case stableSampleTarget
    case temporalStabilityFrames
    case cooldownSeconds
    case recognitionRunMode
    case handUsageMode
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    framesPerSecond = try container.decodeIfPresent(Int.self, forKey: .framesPerSecond) ?? 12
    minimumPointConfidence =
      try container.decodeIfPresent(Double.self, forKey: .minimumPointConfidence) ?? 0.35
    stableSampleTarget =
      try container.decodeIfPresent(Int.self, forKey: .stableSampleTarget) ?? 36
    temporalStabilityFrames =
      try container.decodeIfPresent(Int.self, forKey: .temporalStabilityFrames) ?? 5
    cooldownSeconds =
      try container.decodeIfPresent(Double.self, forKey: .cooldownSeconds) ?? 1.5
    recognitionRunMode =
      try container.decodeIfPresent(RecognitionRunMode.self, forKey: .recognitionRunMode)
      ?? .continuous
    handUsageMode =
      try container.decodeIfPresent(HandUsageMode.self, forKey: .handUsageMode) ?? .both
    sanitize()
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(framesPerSecond, forKey: .framesPerSecond)
    try container.encode(minimumPointConfidence, forKey: .minimumPointConfidence)
    try container.encode(stableSampleTarget, forKey: .stableSampleTarget)
    try container.encode(temporalStabilityFrames, forKey: .temporalStabilityFrames)
    try container.encode(cooldownSeconds, forKey: .cooldownSeconds)
    try container.encode(recognitionRunMode, forKey: .recognitionRunMode)
    try container.encode(handUsageMode, forKey: .handUsageMode)
  }

  mutating func sanitize() {
    framesPerSecond = min(15, max(10, framesPerSecond))
    minimumPointConfidence = min(0.75, max(0.2, minimumPointConfidence))
    stableSampleTarget = min(80, max(24, stableSampleTarget))
    temporalStabilityFrames = min(10, max(3, temporalStabilityFrames))
    cooldownSeconds = min(5.0, max(0.5, cooldownSeconds))
  }
}

struct AppConfiguration: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 3

  var schemaVersion: Int
  var recognitionEnabled: Bool
  var launchAtLogin: Bool
  var gestures: [GestureDefinition]
  var advanced: AdvancedSettings

  static func defaults() -> AppConfiguration {
    AppConfiguration(
      schemaVersion: currentSchemaVersion,
      recognitionEnabled: false,
      launchAtLogin: false,
      gestures: BuiltInGesture.allCases.map {
        GestureDefinition(
          id: UUID(),
          name: $0.rawValue,
          kind: .builtIn($0),
          action: .doNothing,
          template: nil
        )
      },
      advanced: AdvancedSettings()
    )
  }

  mutating func normalize() {
    schemaVersion = Self.currentSchemaVersion
    advanced.sanitize()

    var normalized: [GestureDefinition] = []
    var usedIDs: Set<UUID> = []
    var usedNames: Set<String> = []

    for builtIn in BuiltInGesture.allCases {
      var gesture =
        gestures.first(where: {
          if case .builtIn(let value) = $0.kind { return value == builtIn }
          return false
        })
        ?? GestureDefinition(
          id: UUID(),
          name: builtIn.rawValue,
          kind: .builtIn(builtIn),
          action: .doNothing,
          template: nil
        )
      if usedIDs.contains(gesture.id) { gesture.id = UUID() }
      usedIDs.insert(gesture.id)
      gesture.name = builtIn.rawValue
      gesture.kind = .builtIn(builtIn)
      if gesture.template?.isValid != true
        || gesture.template?.expectedHandCount != builtIn.expectedHandCount
      {
        gesture.template = nil
      }
      usedNames.insert(gesture.name.lowercased())
      normalized.append(gesture)
    }

    for var gesture in gestures where gesture.kind == .custom {
      if usedIDs.contains(gesture.id) { gesture.id = UUID() }
      usedIDs.insert(gesture.id)

      let trimmed = gesture.name.trimmingCharacters(in: .whitespacesAndNewlines)
      let baseName = trimmed.isEmpty ? "Custom Gesture" : trimmed
      gesture.name = Self.uniqueName(baseName, usedNames: &usedNames)
      if gesture.template?.isValid != true { gesture.template = nil }
      normalized.append(gesture)
    }
    gestures = normalized

    if !builtInsCalibrated {
      recognitionEnabled = false
    }
  }

  private static func uniqueName(_ base: String, usedNames: inout Set<String>) -> String {
    if usedNames.insert(base.lowercased()).inserted { return base }
    var number = 2
    while true {
      let candidate = "\(base) \(number)"
      if usedNames.insert(candidate.lowercased()).inserted { return candidate }
      number += 1
    }
  }

  var builtInsCalibrated: Bool {
    BuiltInGesture.allCases.allSatisfy { builtIn in
      gestures.contains {
        guard case .builtIn(let value) = $0.kind else { return false }
        return value == builtIn && $0.template != nil
      }
    }
  }
}

struct ExtractedFeatureVector: Equatable, Sendable {
  var names: [String]
  var values: [Double]
  var weights: [Double]
  var handCount: Int
  var minimumConfidence: Double
  var singleHandSide: HandSide?
}

enum RecordingState: Equatable, Sendable {
  case idle
  case preparing(gestureID: UUID)
  case recording(gestureID: UUID, accepted: Int, target: Int, rejected: Int)
  case completed(gestureID: UUID)
  case failed(gestureID: UUID, message: String)
}

extension Notification.Name {
  static let airControllRecognitionChanged = Notification.Name("AirControllRecognitionChanged")
  static let airControllOpenSettings = Notification.Name("AirControllOpenSettings")
}
