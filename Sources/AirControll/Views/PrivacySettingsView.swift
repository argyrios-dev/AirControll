import AVFoundation
import AppKit
import SwiftUI

struct PrivacySettingsView: View {
  @ObservedObject var model: AppModel
  @ObservedObject private var permissions: PermissionManager
  @State private var confirmDelete = false

  init(model: AppModel) {
    self.model = model
    self.permissions = model.permissionManager
  }

  var body: some View {
    SettingsPage(
      title: "Privacy",
      subtitle: "Review local processing, permissions and stored learned data."
    ) {
      SettingsCard {
        Text("Camera frames are processed locally in memory and are not saved.")
          .font(.headline)
        Text(
          "AirControll has no analytics, telemetry, networking, cloud processing or remote logging. Gesture calibration stores only normalized numeric features and aggregate statistics."
        )
        .foregroundStyle(.secondary)
      }

      SettingsCard {
        permissionRow(
          title: "Camera permission",
          value: permissions.cameraStatusText,
          granted: permissions.cameraStatus == .authorized,
          primaryTitle: permissions.cameraStatus == .notDetermined ? "Request" : "Open Settings",
          primaryAction: {
            if permissions.cameraStatus == .notDetermined {
              permissions.requestCamera()
            } else {
              permissions.openCameraPrivacySettings()
            }
          }
        )
        Divider()
        permissionRow(
          title: "Accessibility permission",
          value: permissions.accessibilityStatusText,
          granted: permissions.accessibilityGranted,
          primaryTitle: permissions.accessibilityGranted ? "Open Settings" : "Request",
          primaryAction: {
            if permissions.accessibilityGranted {
              permissions.openAccessibilityPrivacySettings()
            } else {
              permissions.requestAccessibility()
            }
          }
        )
        Divider()
        LabeledContent("Recognition state") {
          Text(model.recognitionEnabled ? "Enabled" : "Disabled")
        }
      }

      SettingsCard {
        LabeledContent("Application Support folder") {
          Text(model.applicationSupportPath)
            .font(.caption.monospaced())
            .textSelection(.enabled)
        }
        HStack {
          Button("Open Folder") { model.openApplicationSupportFolder() }
          Spacer()
          Button("Delete Learned Data…", role: .destructive) { confirmDelete = true }
        }
      }
    }
    .onAppear { permissions.refresh() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    {
      _ in
      permissions.refresh()
    }
    .confirmationDialog(
      "Delete all learned gesture data?",
      isPresented: $confirmDelete,
      titleVisibility: .visible
    ) {
      Button("Delete Learned Data", role: .destructive) { model.deleteAllLearnedData() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This removes all custom gestures, calibration features, action mappings and saved application bookmarks. It cannot be undone."
      )
    }
  }

  private func permissionRow(
    title: String,
    value: String,
    granted: Bool,
    primaryTitle: String,
    primaryAction: @escaping () -> Void
  ) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Label(value, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
          .font(.caption)
          .foregroundStyle(granted ? Color.green : Color.orange)
      }
      Spacer()
      Button(primaryTitle, action: primaryAction)
    }
  }
}
