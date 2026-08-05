import AppKit
import SwiftUI

struct RootSettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    NavigationSplitView {
      List(
        selection: Binding<SettingsSection?>(
          get: { model.selectedSection },
          set: { if let section = $0 { model.selectedSection = section } }
        )
      ) {
        Section {
          ForEach(SettingsSection.allCases) { section in
            Label(section.rawValue, systemImage: section.systemImage)
              .font(.body.weight(.medium))
              .padding(.vertical, 4)
              .tag(section)
          }
        } header: {
          HStack(spacing: 8) {
            Image(systemName: "hand.raised.fingers.spread.fill")
              .foregroundStyle(Color.accentColor)
            Text("AirControll")
              .font(.headline)
          }
          .textCase(nil)
          .padding(.bottom, 8)
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
      .background(.ultraThinMaterial)
      .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 230)
    } detail: {
      ZStack {
        LinearGradient(
          colors: [
            Color.accentColor.opacity(0.075),
            Color(nsColor: NSColor.windowBackgroundColor).opacity(0.25),
            Color.clear,
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        Group {
          switch model.selectedSection {
          case .general: GeneralSettingsView(model: model)
          case .gestures: GesturesSettingsView(model: model)
          case .actions: ActionsSettingsView(model: model)
          case .privacy: PrivacySettingsView(model: model)
          case .advanced: AdvancedSettingsView(model: model)
          case .about: AboutSettingsView()
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }
    .frame(minWidth: 760, minHeight: 540)
    .alert(
      "AirControll",
      isPresented: Binding(
        get: { model.statusMessage != nil },
        set: { if !$0 { model.clearStatusMessage() } }
      )
    ) {
      Button("OK") { model.clearStatusMessage() }
    } message: {
      Text(model.statusMessage ?? "")
    }
  }
}

struct SettingsPage<Content: View>: View {
  let title: String
  let subtitle: String
  let content: Content

  init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.subtitle = subtitle
    self.content = content()
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 7) {
          Text(title)
            .font(.system(size: 31, weight: .bold, design: .rounded))
          Text(subtitle)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)

        content
      }
      .padding(.horizontal, 30)
      .padding(.top, 28)
      .padding(.bottom, 36)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct SettingsCard<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) { content }
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
      }
      .shadow(color: Color.black.opacity(0.07), radius: 14, x: 0, y: 5)
  }
}
