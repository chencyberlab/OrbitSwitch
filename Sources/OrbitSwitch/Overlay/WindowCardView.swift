import AppKit
import OrbitSwitchCore

final class WindowCardView: NSView {
    let representedID: CGWindowID
    private let imageView = NSImageView()
    private let iconView = NSImageView()
    private let appLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let fallbackLabel = NSTextField(labelWithString: L10n.previewUnavailable)

    init(window: SwitchableWindow, settings: AppSettings) {
        representedID = window.id
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.98).cgColor
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.42).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.55
        layer?.shadowRadius = 30
        layer?.shadowOffset = CGSize(width: 0, height: -12)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 12
        imageView.layer?.masksToBounds = true
        if let preview = window.preview {
            updatePreview(preview)
        }

        fallbackLabel.alignment = .center
        fallbackLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        fallbackLabel.font = .systemFont(ofSize: 16, weight: .medium)
        appLabel.stringValue = window.metadata.appName
        appLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        appLabel.textColor = .white
        appLabel.lineBreakMode = .byTruncatingTail
        titleLabel.stringValue = window.metadata.title.isEmpty ? "Untitled Window" : window.metadata.title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.68)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        iconView.image = window.appIcon
        iconView.imageScaling = .scaleProportionallyUpOrDown

        [imageView, fallbackLabel, iconView, appLabel, titleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        iconView.isHidden = !settings.showAppIcon
        appLabel.isHidden = !settings.showAppName
        titleLabel.isHidden = !settings.showWindowTitle

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -68),
            fallbackLabel.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            fallbackLabel.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -15),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),
            appLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            appLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            appLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -35),
            titleLabel.leadingAnchor.constraint(equalTo: appLabel.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: appLabel.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: appLabel.bottomAnchor, constant: 1)
        ])
        setAccessibilityElement(true)
        setAccessibilityLabel("\(window.metadata.appName), \(titleLabel.stringValue)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func updatePreview(_ preview: CGImage?) {
        guard let preview else { return }
        imageView.image = NSImage(cgImage: preview, size: .zero)
        fallbackLabel.isHidden = true
    }

    func setSelected(_ selected: Bool) {
        layer?.borderWidth = selected ? 3 : 1.5
        layer?.borderColor = selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.95).cgColor
            : NSColor.white.withAlphaComponent(0.25).cgColor
        layer?.shadowOpacity = selected ? 0.75 : 0.45
    }
}
