import PhotosUI
import SwiftUI

/// Multi-select PHPickerViewController wrapper that returns PHAsset local identifiers.
/// Uses PHPickerConfiguration(photoLibrary:) so results include assetIdentifier.
struct ProjectMediaPickerView: UIViewControllerRepresentable {
    var onSelect: ([String]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 0  // 0 = unlimited multi-select
        config.filter = .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onSelect: ([String]) -> Void

        init(onSelect: @escaping ([String]) -> Void) {
            self.onSelect = onSelect
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            let identifiers = results.compactMap { $0.assetIdentifier }
            onSelect(identifiers)
        }
    }
}
