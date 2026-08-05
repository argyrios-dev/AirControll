@preconcurrency import AVFoundation
import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class PermissionManager: ObservableObject {
  @Published private(set) var cameraStatus: AVAuthorizationStatus =
    AVCaptureDevice.authorizationStatus(for: .video)
  @Published private(set) var accessibilityGranted: Bool = AXIsProcessTrusted()

  var cameraStatusText: String {
    switch cameraStatus {
    case .authorized: "Granted"
    case .denied: "Denied"
    case .restricted: "Restricted"
    case .notDetermined: "Not Requested"
    @unknown default: "Unknown"
    }
  }

  var accessibilityStatusText: String { accessibilityGranted ? "Granted" : "Not Granted" }

  func refresh() {
    cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    accessibilityGranted = AXIsProcessTrusted()
  }

  func requestCamera() {
    AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  func requestAccessibility() {
    let options = ["AXTrustedCheckOptionPrompt": true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    refresh()
  }

  func openCameraPrivacySettings() {
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
  }

  func openAccessibilityPrivacySettings() {
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
  }
}
