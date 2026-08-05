import SwiftUI

struct GeneralSettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    SettingsPage(
      title: "General",
      subtitle: "Choose how recognition runs and which hand may trigger one-handed gestures."
    ) {
      SettingsCard {
        HStack(spacing: 12) {
          Image(systemName: model.recognitionEnabled ? "camera.fill" : "camera.slash.fill")
            .font(.title2)
            .foregroundStyle(model.recognitionEnabled ? Color.green : Color.secondary)
            .frame(width: 34, height: 34)
            .background(.thinMaterial, in: Circle())

          VStack(alignment: .leading, spacing: 2) {
            Text(model.recognitionEnabled ? "Recognition is running" : "Recognition is stopped")
              .font(.headline)
            Text(
              model.recognitionEnabled
                ? "Camera frames are being analyzed locally in memory."
                : "The camera is released while recognition is stopped."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }

          Spacer()

          Toggle(
            "Enable hand gesture recognition",
            isOn: Binding(
              get: { model.recognitionEnabled },
              set: { model.setRecognitionEnabled($0) }
            )
          )
          .labelsHidden()
          .toggleStyle(.switch)
          .disabled(!model.builtInsCalibrated && !model.recognitionEnabled)
        }

        if !model.builtInsCalibrated {
          Label(
            "Recognition remains disabled until all four built-in gestures are calibrated.",
            systemImage: "exclamationmark.triangle.fill"
          )
          .foregroundStyle(.orange)
        }
      }

      SettingsCard {
        VStack(alignment: .leading, spacing: 10) {
          Text("Recognition mode")
            .font(.headline)

          Picker(
            "Recognition mode",
            selection: Binding(
              get: { model.configuration.advanced.recognitionRunMode },
              set: { model.setRecognitionRunMode($0) }
            )
          ) {
            ForEach(RecognitionRunMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)

          Text(model.configuration.advanced.recognitionRunMode.explanation)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Divider()

        VStack(alignment: .leading, spacing: 10) {
          Text("Allowed hand")
            .font(.headline)

          Picker(
            "Allowed hand",
            selection: Binding(
              get: { model.configuration.advanced.handUsageMode },
              set: { model.setHandUsageMode($0) }
            )
          ) {
            ForEach(HandUsageMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)

          Text(model.configuration.advanced.handUsageMode.explanation)
            .font(.caption)
            .foregroundStyle(.secondary)

          Label(
            "Praying Hands always requires two hands. Left, Right and Both affect one-handed gestures only.",
            systemImage: "info.circle"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      SettingsCard {
        Toggle(
          "Launch AirControll at login",
          isOn: Binding(
            get: { model.configuration.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
          )
        )

        Divider()

        LabeledContent("Built-in calibration") {
          Text(model.builtInsCalibrated ? "Complete" : "Incomplete")
            .foregroundStyle(model.builtInsCalibrated ? Color.green : Color.orange)
        }
        LabeledContent("Last recognized gesture") {
          Text(model.lastRecognizedGestureName ?? "None")
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}
