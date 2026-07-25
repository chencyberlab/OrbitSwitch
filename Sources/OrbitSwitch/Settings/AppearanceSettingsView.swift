import OrbitSwitchCore
import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section("Switcher Style") {
                Picker("Style", selection: settings.binding(\.overlayStyle)) {
                    ForEach(OverlayStyle.allCases) { style in Text(style.title).tag(style) }
                }
                .pickerStyle(.segmented)
                Text(styleDescription)
                    .foregroundStyle(.secondary)
            }
            switch settings.value.overlayStyle {
            case .orbit: orbitSection
            case .sidebar: sidebarSection
            }
            Section("Labels") {
                Toggle("Show app icon", isOn: settings.binding(\.showAppIcon))
                Toggle("Show app name", isOn: settings.binding(\.showAppName))
                Toggle("Show window title", isOn: settings.binding(\.showWindowTitle))
                Toggle(isOn: settings.binding(\.showWindowControls)) {
                    Text("Show window controls")
                    Text("Close, minimize, and zoom buttons on the front card.")
                }
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

    private var styleDescription: String {
        switch settings.value.overlayStyle {
        case .orbit: "Windows recede into a perspective staircase in the middle of the display."
        case .sidebar: "Windows stack in a strip along one edge of the display, like Stage Manager."
        }
    }

    @ViewBuilder
    private var orbitSection: some View {
        Section("3D Stack") {
            integerSlider("Perspective strength", value: perspectivePercentage, range: 0...100, suffix: "%")
            integerSlider("Stack angle", value: settings.binding(\.stackAngle), range: -28...28, suffix: "°")
            integerSlider("Card spacing", value: settings.binding(\.cardSpacing), range: 24...110, suffix: " pt")
            sharedControls
        }
    }

    @ViewBuilder
    private var sidebarSection: some View {
        Section("Sidebar") {
            Picker("Screen edge", selection: settings.binding(\.sidebarEdge)) {
                ForEach(SidebarEdge.allCases) { edge in Text(edge.title).tag(edge) }
            }
            .pickerStyle(.segmented)
            LabeledContent("Windows on screen") {
                HStack {
                    Slider(
                        value: visibleCount,
                        in: Double(SidebarLayout.visibleCountRange.lowerBound)...Double(SidebarLayout.visibleCountRange.upperBound),
                        step: 1
                    )
                    .frame(width: 250)
                    Text("\(settings.value.sidebarVisibleCount)").monospacedDigit().frame(width: 72, alignment: .trailing)
                }
            }
            integerSlider(
                "Tile width",
                value: settings.binding(\.sidebarTileWidth),
                range: SidebarLayout.tileWidthRange,
                suffix: " pt"
            )
            sharedControls
            Text("Tab keeps cycling through every window. When more windows are open than fit, the strip scrolls and the tiles at each end fade to show the list continues. The strip stays clear of the menu bar and the Dock.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sharedControls: some View {
        decimalSlider("Animation duration", value: settings.binding(\.animationDuration), range: 0.1...0.65, suffix: " s")
        integerSlider("Background dimming", value: settings.binding(\.backgroundBlur), range: 0...85, suffix: "%")
        Picker("Thumbnail quality", selection: settings.binding(\.thumbnailQuality)) {
            ForEach(ThumbnailQuality.allCases) { quality in Text(quality.rawValue.capitalized).tag(quality) }
        }
    }

    private var perspectivePercentage: Binding<Double> {
        Binding(
            get: { settings.value.perspectiveStrength / 0.002 * 100 },
            set: { settings.value.perspectiveStrength = $0 / 100 * 0.002 }
        )
    }

    private var visibleCount: Binding<Double> {
        Binding(
            get: { Double(settings.value.sidebarVisibleCount) },
            set: { settings.value.sidebarVisibleCount = SidebarLayout.clampedVisibleCount(Int($0.rounded())) }
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
