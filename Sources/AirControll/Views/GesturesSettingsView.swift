import SwiftUI

struct GesturesSettingsView: View {
  @ObservedObject var model: AppModel
  @State private var showingAddGesture = false
  @State private var newGestureName = ""
  @State private var gestureToDelete: GestureDefinition?

  var body: some View {
    SettingsPage(
      title: "Gestures",
      subtitle: "Calibrate the built-in gestures and create any number of custom gestures."
    ) {
      recordingStatus

      HStack {
        Text("Gesture Library").font(.headline)
        Spacer()
        Button {
          newGestureName = ""
          showingAddGesture = true
        } label: {
          Label("Add Custom Gesture", systemImage: "plus")
        }
      }

      VStack(spacing: 10) {
        ForEach(model.configuration.gestures) { gesture in
          GestureRow(model: model, gesture: gesture) {
            gestureToDelete = gesture
          }
        }
      }
    }
    .sheet(isPresented: $showingAddGesture) {
      VStack(alignment: .leading, spacing: 16) {
        Text("New Custom Gesture").font(.title2.bold())
        TextField("Gesture name", text: $newGestureName)
          .textFieldStyle(.roundedBorder)
          .onSubmit(addGesture)
        HStack {
          Spacer()
          Button("Cancel") { showingAddGesture = false }
          Button("Add", action: addGesture)
            .keyboardShortcut(.defaultAction)
            .disabled(newGestureName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .padding(24)
      .frame(width: 380)
    }
    .alert(
      gestureToDelete?.isBuiltIn == true ? "Delete Calibration?" : "Delete Gesture?",
      isPresented: Binding(
        get: { gestureToDelete != nil },
        set: { if !$0 { gestureToDelete = nil } }
      ),
      presenting: gestureToDelete
    ) { gesture in
      Button("Cancel", role: .cancel) { gestureToDelete = nil }
      Button("Delete", role: .destructive) {
        model.deleteGesture(id: gesture.id)
        gestureToDelete = nil
      }
    } message: { gesture in
      if gesture.isBuiltIn {
        Text(
          "The learned numeric calibration for \(gesture.name) will be removed. The built-in gesture itself remains available."
        )
      } else {
        Text("\(gesture.name) and its learned numeric calibration will be permanently removed.")
      }
    }
  }

  @ViewBuilder
  private var recordingStatus: some View {
    switch model.recordingState {
    case .idle:
      EmptyView()
    case .preparing:
      SettingsCard {
        ProgressView()
        Text("Preparing the camera…")
      }
    case .recording(let gestureID, let accepted, let target, let rejected):
      SettingsCard {
        HStack {
          VStack(alignment: .leading, spacing: 6) {
            Text("Recording \(model.gesture(id: gestureID)?.name ?? "Gesture")").font(.headline)
            Text(
              "Hold the gesture steady. Low-confidence, missing, moving and inconsistent samples are rejected."
            )
            .foregroundStyle(.secondary)
            ProgressView(value: Double(accepted), total: Double(target))
            Text("\(accepted) of \(target) stable samples • \(rejected) rejected")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("Cancel") { model.cancelRecording() }
        }
      }
    case .completed(let gestureID):
      SettingsCard {
        Label(
          "\(model.gesture(id: gestureID)?.name ?? "Gesture") calibrated successfully.",
          systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(.green)
        Button("Done") { model.cancelRecording() }
      }
    case .failed(_, let message):
      SettingsCard {
        Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        Button("Dismiss") { model.cancelRecording() }
      }
    }
  }

  private func addGesture() {
    model.addCustomGesture(named: newGestureName)
    showingAddGesture = false
  }
}

private struct GestureRow: View {
  @ObservedObject var model: AppModel
  let gesture: GestureDefinition
  let requestDelete: () -> Void

  var body: some View {
    SettingsCard {
      HStack(alignment: .center, spacing: 14) {
        Image(systemName: gesture.isBuiltIn ? "hand.raised.fill" : "hand.draw.fill")
          .font(.title2)
          .frame(width: 30)
        VStack(alignment: .leading, spacing: 3) {
          HStack {
            Text(gesture.name).font(.headline)
            if gesture.isBuiltIn {
              Text("BUILT-IN")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.15), in: Capsule())
            }
          }
          Text(gesture.isCalibrated ? calibrationDescription : "Not calibrated")
            .font(.caption)
            .foregroundStyle(gesture.isCalibrated ? Color.secondary : Color.orange)
        }
        Spacer()
        Button(gesture.isCalibrated ? "Re-record" : "Record") {
          model.beginRecording(gestureID: gesture.id)
        }
        Button(role: .destructive, action: requestDelete) {
          Image(systemName: "trash")
        }
        .help(gesture.isBuiltIn ? "Delete calibration" : "Delete gesture")
      }
    }
  }

  private var calibrationDescription: String {
    guard let template = gesture.template else { return "Not calibrated" }
    return
      "Calibrated • \(template.sampleCount) samples • \(template.recordingDate.formatted(date: .abbreviated, time: .shortened))"
  }
}
