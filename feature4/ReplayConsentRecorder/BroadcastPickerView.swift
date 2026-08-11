import ReplayKit
import SwiftUI

struct BroadcastPickerView: UIViewRepresentable {
    let isEnabled: Bool
    let activationID: Int

    func makeUIView(context: Context) -> BroadcastPickerContainerView {
        let container = BroadcastPickerContainerView()
        configure(container, context: context)
        return container
    }

    func updateUIView(_ container: BroadcastPickerContainerView, context: Context) {
        configure(container, context: context)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func configure(_ container: BroadcastPickerContainerView, context: Context) {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            container.picker.preferredExtension = "\(bundleIdentifier).BroadcastUploadExtension"
        }

        container.picker.showsMicrophoneButton = false
        container.isUserInteractionEnabled = isEnabled
        container.alpha = isEnabled ? 1 : 0.45
        container.setNeedsLayout()

        guard isEnabled, activationID > context.coordinator.lastActivationID else {
            return
        }

        context.coordinator.lastActivationID = activationID

        DispatchQueue.main.async {
            container.presentPicker()
        }
    }

    final class Coordinator {
        var lastActivationID = 0
    }
}

final class BroadcastPickerContainerView: UIView {
    let picker = RPSystemBroadcastPickerView(frame: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        picker.backgroundColor = .clear
        addSubview(picker)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        picker.frame = bounds
        configurePickerButton()
    }

    func presentPicker() {
        setNeedsLayout()
        layoutIfNeeded()

        guard let button = picker.subviews.compactMap({ $0 as? UIButton }).first else {
            return
        }

        button.sendActions(for: .touchUpInside)
    }

    private func configurePickerButton() {
        for case let button as UIButton in picker.subviews {
            button.frame = picker.bounds
            button.tintColor = .clear
            button.backgroundColor = .clear
            button.imageView?.isHidden = true
            button.accessibilityLabel = "Start Phone Screen Recording"
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, bounds.contains(point) else {
            return nil
        }

        return picker.hitTest(convert(point, to: picker), with: event) ?? picker
    }
}
