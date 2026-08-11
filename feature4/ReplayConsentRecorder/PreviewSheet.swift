import ReplayKit
import SwiftUI

struct ReplayPreviewSheet: UIViewControllerRepresentable {
    let previewController: RPPreviewViewController
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> RPPreviewViewController {
        previewController.previewControllerDelegate = context.coordinator
        return previewController
    }

    func updateUIViewController(_ uiViewController: RPPreviewViewController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    final class Coordinator: NSObject, RPPreviewViewControllerDelegate {
        private let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
            previewController.dismiss(animated: true)
            onDismiss()
        }
    }
}
