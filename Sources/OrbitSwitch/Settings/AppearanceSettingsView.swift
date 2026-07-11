import OrbitSwitchCore
import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section("3D Stack") {
                integerSlider("Perspective strength", value: perspectivePercentage, range: 0...100, suffix: "%")
                integerSlider("Stack angle", value: settings.binding(\.stackAngle), range: 0...28, suffix: "°")
                integerSlider("Card spacing", value: settings.binding(\.cardSpacing), range: 24...110, suffix: " pt")
                decimalSlider("Animation duration", value: settings.binding(\.animationDuration), range: 0.1...0.65, suffix: " s")
                integerSlider("Background dimming", value: settings.binding(\.backgroundBlur), range: 0...85, suffix: "%")
                Picker("Thumbnail quality", selection: settings.binding(\.thumbnailQuality)) {
                    ForEach(ThumbnailQuality.allCases) { quality in Text(quality.rawValue.capitalized).tag(quality) }
                }
            }
            Section("Labels") {
                Toggle("Show app icon", isOn: settings.binding(\.showAppIcon))
                Toggle("Show app name", isOn: settings.binding(\.showAppName))
                Toggle("Show window title", isOn: settings.binding(\.showWindowTitle))
                Picker("Theme", selection: settings.binding(\.theme)) {
                    ForEach(AppTheme.allCases) { theme in Text(theme.rawValue.capitalized).tag(theme) }
                }
            }
            Text("OrbitSwitch automatically follows the system Reduce Motion and Increase Contrast settings.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    private var perspectivePercentage: Binding<Double> {
        Binding(
            get: { settings.value.perspectiveStrength / 0.002 * 100 },
            set: { settings.value.perspectiveStrength = $0 / 100 * 0.002 }
        )
    }

    @ViewBuilder
    private func integerSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: 1).frame(width: 250)
                Text("\(Int(value.wrappedValue.rounded()))\(suffix)").monospacedDigit().frame(width: 72, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func decimalSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range).frame(width: 250)
                Text("\(value.wrappedValue, specifier: "%.2f")\(suffix)").monospacedDigit().frame(width: 72, alignment: .trailing)
            }
        }
    }
}
