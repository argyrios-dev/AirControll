import SwiftUI

struct AdvancedSettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    SettingsPage(
      title: "Advanced",
      subtitle: "Tune deterministic local recognition while keeping capture between 10 and 15 FPS."
    ) {
      SettingsCard {
        HStack {
          Text("Processing frame rate")
          Spacer()
          Text("\(model.configuration.advanced.framesPerSecond) FPS")
            .foregroundStyle(.secondary)
          Stepper(
            "",
            value: Binding(
              get: { model.configuration.advanced.framesPerSecond },
              set: { value in mutate { $0.framesPerSecond = value } }
            ),
            in: 10...15
          )
          .labelsHidden()
        }

        Divider()

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Minimum landmark confidence")
            Spacer()
            Text(
              model.configuration.advanced.minimumPointConfidence,
              format: .number.precision(.fractionLength(2))
            )
            .foregroundStyle(.secondary)
          }
          Slider(
            value: Binding(
              get: { model.configuration.advanced.minimumPointConfidence },
              set: { value in mutate { $0.minimumPointConfidence = value } }
            ),
            in: 0.2...0.75,
            step: 0.05
          )
        }

        Divider()

        HStack {
          Text("Stable recording samples")
          Spacer()
          Text("\(model.configuration.advanced.stableSampleTarget)")
            .foregroundStyle(.secondary)
          Stepper(
            "",
            value: Binding(
              get: { model.configuration.advanced.stableSampleTarget },
              set: { value in mutate { $0.stableSampleTarget = value } }
            ),
            in: 24...80
          )
          .labelsHidden()
        }

        Divider()

        HStack {
          Text("Temporal stability frames")
          Spacer()
          Text("\(model.configuration.advanced.temporalStabilityFrames)")
            .foregroundStyle(.secondary)
          Stepper(
            "",
            value: Binding(
              get: { model.configuration.advanced.temporalStabilityFrames },
              set: { value in mutate { $0.temporalStabilityFrames = value } }
            ),
            in: 3...10
          )
          .labelsHidden()
        }

        Divider()

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Trigger cooldown")
            Spacer()
            Text("\(model.configuration.advanced.cooldownSeconds, specifier: "%.1f") seconds")
              .foregroundStyle(.secondary)
          }
          Slider(
            value: Binding(
              get: { model.configuration.advanced.cooldownSeconds },
              set: { value in mutate { $0.cooldownSeconds = value } }
            ),
            in: 0.5...5.0,
            step: 0.1
          )
        }
      }

      Text(
        "Matching uses deterministic weighted Euclidean distance, per-feature variance, learned thresholds, temporal stability, cooldown and release-based duplicate prevention."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private func mutate(_ body: (inout AdvancedSettings) -> Void) {
    var settings = model.configuration.advanced
    body(&settings)
    model.setAdvanced(settings)
  }
}
