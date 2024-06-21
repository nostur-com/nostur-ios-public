//
//  VideoPickerView.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/06/2024.
//

import SwiftUI
import UIKit
import MobileCoreServices
import AVFoundation

struct VideoPickerView: UIViewControllerRepresentable {
    @Binding var selectedVideoURL: URL?
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: VideoPickerView

        init(parent: VideoPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let mediaType = info[.mediaType] as? String, mediaType == (kUTTypeMovie as String) {
                if let url = info[.mediaURL] as? URL {
                    parent.selectedVideoURL = url
                }
            }
            picker.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.mediaTypes = [kUTTypeMovie as String]
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
}

// Compress video
func compressVideo(inputURL: URL, outputURL: URL, handler:@escaping (AVAssetExportSession.Status) -> Void) {
    let asset = AVAsset(url: inputURL)
    let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality)!
    
    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.metadata = []
    exportSession.exportAsynchronously {
        handler(exportSession.status)
    }
}

func compressVideoSynchronously(inputURL: URL, outputURL: URL) -> URL? {
    let semaphore = DispatchSemaphore(value: 0)
    var resultURL: URL? = nil
    
    compressVideo(inputURL: inputURL, outputURL: outputURL) { status in
        if status == .completed {
            resultURL = outputURL
        }
        semaphore.signal()
    }
    
    semaphore.wait()
    return resultURL
}
