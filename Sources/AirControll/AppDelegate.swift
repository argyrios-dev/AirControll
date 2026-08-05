import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private let model = AppModel.shared
  private var statusItem: NSStatusItem?
  private var recognitionMenuItem: NSMenuItem?
  private var settingsWindow: NSWindow?
  private var cancellables: Set<AnyCancellable> = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    configureMainMenu()
    configureStatusItem()
    configureObservers()
    showSettingsWindow()
  }

  func applicationWillTerminate(_ notification: Notification) {
    model.shutdown()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showSettingsWindow()
    return true
  }

  private func configureObservers() {
    model.$configuration
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.updateRecognitionMenuItem() }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: .airControllOpenSettings)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.showSettingsWindow() }
      .store(in: &cancellables)
  }

  private func configureMainMenu() {
    let mainMenu = NSMenu()
    let applicationItem = NSMenuItem()
    mainMenu.addItem(applicationItem)

    let applicationMenu = NSMenu()
    let aboutItem = NSMenuItem(
      title: "About AirControll", action: #selector(showAbout), keyEquivalent: "")
    aboutItem.target = self
    applicationMenu.addItem(aboutItem)
    applicationMenu.addItem(NSMenuItem.separator())
    let settingsItem = NSMenuItem(
      title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    settingsItem.target = self
    applicationMenu.addItem(settingsItem)
    applicationMenu.addItem(NSMenuItem.separator())
    let quitItem = NSMenuItem(
      title: "Quit AirControll", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    quitItem.target = NSApp
    applicationMenu.addItem(quitItem)
    applicationItem.submenu = applicationMenu
    NSApp.mainMenu = mainMenu
  }

  private func configureStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem = item
    item.button?.image = Self.makeStatusTemplateImage()
    item.button?.imagePosition = .imageOnly
    item.button?.imageScaling = .scaleProportionallyDown
    item.button?.toolTip = "AirControll"

    let menu = NSMenu()
    let recognition = NSMenuItem(
      title: "Enable Recognition", action: #selector(toggleRecognition), keyEquivalent: "")
    recognition.target = self
    menu.addItem(recognition)
    recognitionMenuItem = recognition

    let settings = NSMenuItem(
      title: "Open Settings…", action: #selector(openSettings), keyEquivalent: "")
    settings.target = self
    menu.addItem(settings)
    menu.addItem(.separator())

    let quit = NSMenuItem(
      title: "Quit AirControll", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    quit.target = NSApp
    menu.addItem(quit)
    item.menu = menu
    updateRecognitionMenuItem()
  }

  private func updateRecognitionMenuItem() {
    recognitionMenuItem?.title =
      model.recognitionEnabled ? "Disable Recognition" : "Enable Recognition"
    recognitionMenuItem?.state = model.recognitionEnabled ? .on : .off
  }

  @objc private func toggleRecognition() {
    model.toggleRecognition()
  }

  @objc private func openSettings() {
    showSettingsWindow()
  }

  @objc private func showAbout() {
    model.selectedSection = .about
    showSettingsWindow()
  }

  private func showSettingsWindow() {
    if settingsWindow == nil {
      let rootView = RootSettingsView(model: model)
      let controller = NSHostingController(rootView: rootView)
      let window = NSWindow(contentViewController: controller)
      window.title = "AirControll"
      window.setContentSize(NSSize(width: 920, height: 650))
      window.minSize = NSSize(width: 760, height: 540)
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.toolbarStyle = .unifiedCompact
      window.isMovableByWindowBackground = true
      window.isReleasedWhenClosed = false
      window.center()
      window.delegate = self
      settingsWindow = window
    }
    settingsWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    return false
  }

  private static func makeStatusTemplateImage() -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size, flipped: false) { rect in
      guard let context = NSGraphicsContext.current?.cgContext else { return false }
      context.saveGState()
      context.translateBy(x: rect.midX, y: rect.midY)
      context.rotate(by: .pi / 4.0)

      let coordinates: [CGFloat] = [-3.25, 0, 3.25]
      for x in coordinates {
        for y in coordinates {
          let outer = NSRect(x: x - 1.45, y: y - 1.45, width: 2.9, height: 2.9)
          NSColor.labelColor.withAlphaComponent(0.18).setFill()
          NSBezierPath(ovalIn: outer).fill()

          let core = NSRect(x: x - 1.05, y: y - 1.05, width: 2.1, height: 2.1)
          NSColor.labelColor.withAlphaComponent(0.90).setFill()
          NSBezierPath(ovalIn: core).fill()

          let highlight = NSRect(x: x - 0.58, y: y + 0.10, width: 0.72, height: 0.58)
          NSColor.labelColor.withAlphaComponent(0.34).setFill()
          NSBezierPath(ovalIn: highlight).fill()
        }
      }

      context.restoreGState()
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "AirControll liquid gesture grid"
    return image
  }
}
