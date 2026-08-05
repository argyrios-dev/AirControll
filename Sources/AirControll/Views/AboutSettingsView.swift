import AppKit
import SwiftUI

struct AboutSettingsView: View {
  var body: some View {
    SettingsPage(
      title: "About",
      subtitle: "AirControll version \(airControllVersion)"
    ) {
      SettingsCard {
        HStack(alignment: .center, spacing: 20) {
          Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 96, height: 96)
          VStack(alignment: .leading, spacing: 6) {
            Text("AirControll").font(.title.bold())
            Text("Version \(airControllVersion)")
            Text("Native offline hand gesture control for macOS.")
              .foregroundStyle(.secondary)
            Text("Created by Argyrios")
              .font(.subheadline.weight(.medium))
          }
        }
      }

      SettingsCard {
        Label("AVFoundation camera capture", systemImage: "camera")
        Label("Vision hand-pose recognition", systemImage: "hand.raised")
        Label(
          "No networking, analytics, telemetry or cloud processing", systemImage: "network.slash")
        Label(
          "Configuration stored locally with atomic writes",
          systemImage: "externaldrive.badge.checkmark")
      }

      Text("Copyright © 2026 Argyrios. Licensed under the Mozilla Public License 2.0.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
