import AppKit
import ApplicationServices
import Carbon
import Foundation

@MainActor
final class ActionExecutor {
  func execute(_ action: GestureAction) throws {
    if action.requiresAccessibility && !AXIsProcessTrusted() {
      throw ActionExecutionError.accessibilityRequired
    }

    switch action {
    case .playPause:
      try runMediaCommand("playpause")
    case .nextTrack:
      try runMediaCommand("next track")
    case .previousTrack:
      try runMediaCommand("previous track")
    case .volumeUp:
      try runAppleScript(
        """
        set currentVolume to output volume of (get volume settings)
        set newVolume to currentVolume + 6
        if newVolume > 100 then set newVolume to 100
        set volume output volume newVolume
        """)
    case .volumeDown:
      try runAppleScript(
        """
        set currentVolume to output volume of (get volume settings)
        set newVolume to currentVolume - 6
        if newVolume < 0 then set newVolume to 0
        set volume output volume newVolume
        """)
    case .mute:
      try runAppleScript(
        """
        set isMuted to output muted of (get volume settings)
        if isMuted then
            set volume without output muted
        else
            set volume with output muted
        end if
        """)
    case .brightnessUp:
      try postKey(CGKeyCode(kVK_F2), flags: [])
    case .brightnessDown:
      try postKey(CGKeyCode(kVK_F1), flags: [])
    case .missionControl:
      try postKey(CGKeyCode(kVK_UpArrow), flags: [.maskControl])
    case .showDesktop:
      try postKey(CGKeyCode(kVK_F11), flags: [.maskSecondaryFn])
    case .lockScreen:
      try postKey(CGKeyCode(kVK_ANSI_Q), flags: [.maskControl, .maskCommand])
    case .screenshot:
      try postKey(CGKeyCode(kVK_ANSI_3), flags: [.maskCommand, .maskShift])
    case .openApplication(let bookmark):
      guard let bookmark else { throw ActionExecutionError.applicationNotSelected }
      try openApplication(bookmark)
    case .keyboardShortcut(let shortcut):
      guard let shortcut else { throw ActionExecutionError.shortcutNotRecorded }
      let flags = CGEventFlags(rawValue: shortcut.modifierFlagsRawValue)
      if shortcut.isModifierOnly {
        try postModifierOnly(flags)
      } else {
        try postKey(CGKeyCode(shortcut.keyCode), flags: flags)
      }
    case .doNothing:
      break
    }
  }

  private func runMediaCommand(_ command: String) throws {
    let source = """
      if application "Music" is running then
          tell application "Music" to \(command)
      else if application "Spotify" is running then
          tell application "Spotify" to \(command)
      else
          tell application "Music" to \(command)
      end if
      """
    try runAppleScript(source)
  }

  private func runAppleScript(_ source: String) throws {
    guard let script = NSAppleScript(source: source) else {
      throw ActionExecutionError.appleScriptFailed("The AppleScript could not be created.")
    }
    var errorInfo: NSDictionary?
    script.executeAndReturnError(&errorInfo)
    if let errorInfo {
      let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
      throw ActionExecutionError.appleScriptFailed(message)
    }
  }

  private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) throws {
    guard
      let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
      let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    else { throw ActionExecutionError.eventCreationFailed }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
  }

  private func postModifierOnly(_ flags: CGEventFlags) throws {
    let modifiers: [(flag: CGEventFlags, keyCode: CGKeyCode)] = [
      (.maskControl, 59),
      (.maskAlternate, 58),
      (.maskShift, 56),
      (.maskCommand, 55),
      (.maskSecondaryFn, 63),
    ].filter { flags.contains($0.flag) }

    guard !modifiers.isEmpty else {
      throw ActionExecutionError.eventCreationFailed
    }

    var activeFlags: CGEventFlags = []
    for modifier in modifiers {
      activeFlags.insert(modifier.flag)
      try postModifierChange(keyCode: modifier.keyCode, flags: activeFlags)
    }
    for modifier in modifiers.reversed() {
      activeFlags.remove(modifier.flag)
      try postModifierChange(keyCode: modifier.keyCode, flags: activeFlags)
    }
  }

  private func postModifierChange(keyCode: CGKeyCode, flags: CGEventFlags) throws {
    guard
      let event = CGEvent(
        keyboardEventSource: nil,
        virtualKey: keyCode,
        keyDown: true
      )
    else {
      throw ActionExecutionError.eventCreationFailed
    }
    event.type = .flagsChanged
    event.flags = flags
    event.post(tap: .cghidEventTap)
  }

  private func openApplication(_ bookmark: ApplicationBookmark) throws {
    var stale = false
    let url = try URL(
      resolvingBookmarkData: bookmark.bookmarkData,
      options: [.withSecurityScope, .withoutUI],
      relativeTo: nil,
      bookmarkDataIsStale: &stale
    )
    guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
      FileManager.default.fileExists(atPath: url.path)
    else {
      throw ActionExecutionError.invalidApplicationBookmark
    }
    let accessed = url.startAccessingSecurityScopedResource()
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
      if accessed { url.stopAccessingSecurityScopedResource() }
      if let error {
        NSLog("AirControll could not open application: %@", error.localizedDescription)
      }
    }
  }
}

enum ActionExecutionError: LocalizedError {
  case accessibilityRequired
  case applicationNotSelected
  case shortcutNotRecorded
  case invalidApplicationBookmark
  case eventCreationFailed
  case appleScriptFailed(String)

  var errorDescription: String? {
    switch self {
    case .accessibilityRequired: "Accessibility permission is required for this action."
    case .applicationNotSelected: "No application has been selected for this action."
    case .shortcutNotRecorded: "No keyboard shortcut has been recorded for this action."
    case .invalidApplicationBookmark: "The selected application is no longer available."
    case .eventCreationFailed: "The keyboard event could not be created."
    case .appleScriptFailed(let message): "The system action failed: \(message)"
    }
  }
}
