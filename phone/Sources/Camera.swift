import SwiftUI
import UIKit

/// The camera, as one screen that hands back one photograph.
///
/// `PhotosPicker` covers the library and is pure SwiftUI; taking a picture is
/// still UIKit's, so this is the smaller of the two wrappers rather than a
/// preference for the old framework.
struct CameraCapture: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let dismiss: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            defer { dismiss() }
            guard let image = info[.originalImage] as? UIImage else { return }
            // Handed over whole. **It used to be encoded here at full size and
            // never resized at all** — a photograph taken in the app was stored
            // at whatever the camera gave. Sizing belongs in one place.
            onCapture(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
