//
//  VineVideoPicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/03/2026.
//

import SwiftUI
import PhotosUI

/// Video picker using PHPickerViewController — no confirmation screen, returns immediately after selection
struct VineVideoPicker: UIViewControllerRepresentable {
    @Binding var selectedVideoURL: URL?
    @Binding var isLoading: Bool
    @Environment(\.dismiss) private var dismiss
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VineVideoPicker
        
        init(_ parent: VineVideoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                return
            }
            
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
            
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                guard let url, error == nil else {
                    DispatchQueue.main.async {
                        self.parent.isLoading = false
                    }
                    return
                }
                
                // Copy to temp location since the provided URL is temporary
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    DispatchQueue.main.async {
                        self.parent.isLoading = false
                        self.parent.selectedVideoURL = tempURL
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.parent.isLoading = false
                    }
                }
            }
        }
    }
}
