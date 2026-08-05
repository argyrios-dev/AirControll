import AppKit
import ApplicationServices
import Carbon
import SwiftUI

struct ActionsSettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    SettingsPage(
      title: "Actions",
      subtitle: "Map every gesture to a system action, application or keyboard shortcut."
    ) {
      VStack(spacing: 12) {
        ForEach(model.configuration.gestures) { gesture in
          ActionMappingRow(model: model, gestureID: gesture.id)
        }
      }
    }
  }
}

private struct ActionMappingRow: View {
  @ObservedObject var model: AppModel
  let gestureID: UUID

  private var gesture: GestureDefinition? { model.gesture(id: gestureID) }

  private var actionKindBinding: Binding<ActionKind> {
    Binding(
      get: { ActionKind(action: gesture?.action ?? .doNothing) },
      set: { kind in
        let existing = gesture?.action ?? .doNothing
        let bookmark: ApplicationBookmark?
        let shortcut: KeyboardShortcut?
        if case .openApplication(let value) = existing { bookmark = value } else { bookmark = nil }
        if case .keyboardShortcut(let value) = existing { shortcut = value } else { shortcut = nil }
        model.updateAction(
          for: gestureID,
          action: kind.makeAction(bookmark: bookmark, shortcut: shortcut)
        )
      }
    )
  }

  var body: some View {
    SettingsCard {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text(gesture?.name ?? "Gesture").font(.headline)
          Text(gesture?.isCalibrated == true ? "Calibrated" : "Not calibrated")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Picker("Action", selection: actionKindBinding) {
          ForEach(ActionKind.allCases) { kind in
            Text(kind.rawValue).tag(kind)
          }
        }
        .labelsHidden()
        .frame(width: 220)
      }

      if let action = gesture?.action {
        actionDetails(action)
      }
    }
  }

  @ViewBuilder
  private func actionDetails(_ action: GestureAction) -> some View {
    switch action {
    case .openApplication(let bookmark):
      HStack {
        Label(bookmark?.displayName ?? "No application selected", systemImage: "app")
          .foregroundStyle(bookmark == nil ? Color.orange : Color.secondary)
        Spacer()
        Button(bookmark == nil ? "Choose Application…" : "Change…") {
          model.chooseApplication(for: gestureID)
        }
      }
    case .keyboardShortcut(let shortcut):
      VStack(alignment: .leading, spacing: 8) {
        Text(
          "Click the recorder, then press a shortcut. Modifier-only shortcuts such as Command or fn are supported."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        HStack(spacing: 10) {
          ShortcutRecorder(
            shortcut: Binding(
              get: { shortcut },
              set: { model.updateAction(for: gestureID, action: .keyboardShortcut($0)) }
            )
          )
          .frame(height: 38)

          Menu("Presets") {
            Button("⌘") {
              saveShortcut(
                keyCode: UInt16(kVK_Command),
                flags: [.maskCommand],
                displayText: "⌘",
                modifierOnly: true
              )
            }
            Button("fn") {
              saveShortcut(
                keyCode: 63,
                flags: [.maskSecondaryFn],
                displayText: "fn",
                modifierOnly: true
              )
            }
            Divider()
            Button("⌘Space") {
              saveShortcut(
                keyCode: UInt16(kVK_Space),
                flags: [.maskCommand],
                displayText: "⌘Space"
              )
            }
            Button("⌃⇧⌘3") {
              saveShortcut(
                keyCode: UInt16(kVK_ANSI_3),
                flags: [.maskControl, .maskShift, .maskCommand],
                displayText: "⌃⇧⌘3"
              )
            }
          }

          Button("Clear") {
            model.updateAction(for: gestureID, action: .keyboardShortcut(nil))
          }
          .disabled(shortcut == nil)
        }

        Label(
          "Examples: ⌘Space, ⌃⇧⌘3, fn, arrow keys and F1–F20.",
          systemImage: "keyboard"
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Label(
          "Keyboard shortcuts require Accessibility permission.",
          systemImage: "accessibility"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    default:
      if action.requiresAccessibility {
        Label("This action requires Accessibility permission.", systemImage: "accessibility")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func saveShortcut(
    keyCode: UInt16,
    flags: CGEventFlags,
    displayText: String,
    modifierOnly: Bool = false
  ) {
    model.updateAction(
      for: gestureID,
      action: .keyboardShortcut(
        KeyboardShortcut(
          keyCode: keyCode,
          modifierFlagsRawValue: flags.rawValue,
          displayText: displayText,
          isModifierOnly: modifierOnly
        )
      )
    )
  }
}

private struct ShortcutRecorder: NSViewRepresentable {
  @Binding var shortcut: KeyboardShortcut?

  @MainActor
  final class Coordinator {
    var shortcut: Binding<KeyboardShortcut?>

    init(shortcut: Binding<KeyboardShortcut?>) {
      self.shortcut = shortcut
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(shortcut: $shortcut)
  }

  func makeNSView(context: Context) -> ShortcutCaptureView {
    let view = ShortcutCaptureView()
    view.onShortcut = { value in
      context.coordinator.shortcut.wrappedValue = value
    }
    view.onClear = {
      context.coordinator.shortcut.wrappedValue = nil
    }
    return view
  }

  func updateNSView(_ nsView: ShortcutCaptureView, context: Context) {
    context.coordinator.shortcut = $shortcut
    nsView.displayText = shortcut?.displayText ?? "Click to record shortcut"
    nsView.needsDisplay = true
  }
}

private final class ShortcutCaptureView: NSView {
  var onShortcut: ((KeyboardShortcut) -> Void)?
  var onClear: (() -> Void)?
  var displayText = "Click to record shortcut"

  private var isRecording = false
  private var pendingModifierFlags: NSEvent.ModifierFlags = []
  private var lastModifierKeyCode: UInt16 = 0

  override var acceptsFirstResponder: Bool { true }
  override var focusRingMaskBounds: NSRect { bounds }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    isRecording = true
    pendingModifierFlags = []
    lastModifierKeyCode = 0
    needsDisplay = true
  }

  override func resignFirstResponder() -> Bool {
    isRecording = false
    pendingModifierFlags = []
    needsDisplay = true
    return super.resignFirstResponder()
  }

  override func flagsChanged(with event: NSEvent) {
    guard isRecording else { return }
    let modifiers = Self.cleanedModifiers(event.modifierFlags)

    if !modifiers.isEmpty {
      pendingModifierFlags.formUnion(modifiers)
      lastModifierKeyCode = event.keyCode
      needsDisplay = true
      return
    }

    guard !pendingModifierFlags.isEmpty else { return }
    let text = Self.modifierDisplayString(pendingModifierFlags)
    let shortcut = KeyboardShortcut(
      keyCode: lastModifierKeyCode,
      modifierFlagsRawValue: Self.cgFlags(from: pendingModifierFlags).rawValue,
      displayText: text,
      isModifierOnly: true
    )
    finishRecording(shortcut)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard isRecording else { return super.performKeyEquivalent(with: event) }
    captureKeyEvent(event)
    return true
  }

  override func keyDown(with event: NSEvent) {
    captureKeyEvent(event)
  }

  private func captureKeyEvent(_ event: NSEvent) {
    let modifiers = Self.cleanedModifiers(event.modifierFlags)

    if event.keyCode == 53 && modifiers.isEmpty {
      if isRecording {
        isRecording = false
        pendingModifierFlags = []
      } else {
        onClear?()
      }
      needsDisplay = true
      return
    }

    guard isRecording else { return }
    guard !Self.modifierOnlyKeyCodes.contains(event.keyCode) else { return }

    let text = Self.displayString(
      keyCode: event.keyCode,
      characters: event.charactersIgnoringModifiers,
      modifiers: modifiers
    )
    let shortcut = KeyboardShortcut(
      keyCode: event.keyCode,
      modifierFlagsRawValue: Self.cgFlags(from: modifiers).rawValue,
      displayText: text,
      isModifierOnly: false
    )
    finishRecording(shortcut)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let path = NSBezierPath(
      roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
      xRadius: 9,
      yRadius: 9
    )
    (isRecording
      ? NSColor.controlAccentColor.withAlphaComponent(0.16)
      : NSColor.controlBackgroundColor.withAlphaComponent(0.82))
      .setFill()
    path.fill()
    (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
    path.lineWidth = isRecording ? 2 : 1
    path.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 13, weight: isRecording ? .semibold : .regular),
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: paragraph,
    ]

    let value: String
    if isRecording, !pendingModifierFlags.isEmpty {
      value = Self.modifierDisplayString(pendingModifierFlags) + " …"
    } else if isRecording {
      value = "Press shortcut…"
    } else {
      value = displayText
    }

    let size = value.size(withAttributes: attributes)
    value.draw(
      in: NSRect(
        x: 8,
        y: (bounds.height - size.height) / 2,
        width: bounds.width - 16,
        height: size.height
      ),
      withAttributes: attributes
    )
  }

  private func finishRecording(_ shortcut: KeyboardShortcut) {
    displayText = shortcut.displayText
    isRecording = false
    pendingModifierFlags = []
    lastModifierKeyCode = 0
    onShortcut?(shortcut)
    needsDisplay = true
  }

  private static let modifierOnlyKeyCodes: Set<UInt16> = [
    54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
  ]

  private static func cleanedModifiers(
    _ flags: NSEvent.ModifierFlags
  ) -> NSEvent.ModifierFlags {
    flags.intersection([.command, .option, .control, .shift, .function])
  }

  private static func cgFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
    var result: CGEventFlags = []
    if flags.contains(.command) { result.insert(.maskCommand) }
    if flags.contains(.option) { result.insert(.maskAlternate) }
    if flags.contains(.control) { result.insert(.maskControl) }
    if flags.contains(.shift) { result.insert(.maskShift) }
    if flags.contains(.function) { result.insert(.maskSecondaryFn) }
    return result
  }

  private static func modifierDisplayString(_ modifiers: NSEvent.ModifierFlags) -> String {
    var text = ""
    if modifiers.contains(.control) { text += "⌃" }
    if modifiers.contains(.option) { text += "⌥" }
    if modifiers.contains(.shift) { text += "⇧" }
    if modifiers.contains(.command) { text += "⌘" }
    if modifiers.contains(.function) { text += "fn" }
    return text
  }

  private static func displayString(
    keyCode: UInt16,
    characters: String?,
    modifiers: NSEvent.ModifierFlags
  ) -> String {
    let prefix = modifierDisplayString(modifiers)

    let special: [UInt16: String] = [
      36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
      71: "Clear", 76: "⌅",
      115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟",
      123: "←", 124: "→", 125: "↓", 126: "↑",
      122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
      98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
      105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
      80: "F19", 90: "F20",
    ]
    if let value = special[keyCode] { return prefix + value }

    let value = characters?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    return prefix + ((value?.isEmpty == false) ? value! : "Key \(keyCode)")
  }
}
