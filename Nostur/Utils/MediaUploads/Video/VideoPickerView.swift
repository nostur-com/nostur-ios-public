//
//  VideoPickerView.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/06/2024.
//

import SwiftUI
import UIKit
import MobileCoreServices

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

import AVFoundation

func compressVideo(inputURL: URL, outputURL: URL, handler:@escaping (AVAssetExportSession.Status) -> Void) {
    let asset = AVAsset(url: inputURL)
    let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality)!
    
    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.exportAsynchronously {
        handler(exportSession.status)
    }
}

// Upload video

func uploadVideo(url: URL, completion: @escaping (Result<Bool, Error>) -> Void) {
    var request = URLRequest(url: URL(string: "http://localhost:8080/wp-json/nostrmedia/v1/upload/")!)
    request.httpMethod = "POST"

    let boundary = UUID().uuidString
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    let data = createBody(with: ["file": url], boundary: boundary)
    let task = URLSession.shared.uploadTask(with: request, from: data) { data, response, error in
        defer {
            // Cleanup the temporary file
            try? FileManager.default.removeItem(at: url)
        }
        
        if let error = error {
            completion(.failure(error))
            return
        }

        completion(.success(true))
    }
    task.resume()
}


func createBody(with parameters: [String: URL], boundary: String) -> Data {
    var body = Data()

    for (key, url) in parameters {
        let filename = url.lastPathComponent
        let data = try! Data(contentsOf: url)
        let mimetype = "video/mp4"

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimetype)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }

    body.append("--\(boundary)--\r\n".data(using: .utf8)!)
    return body
}

//

struct VideoButton: View {
    @State private var selectedVideoURL: URL?
    @State private var isShowingVideoPicker = false
    @State private var isUploading = false
    @State private var uploadStatus: String = ""
    
    var body: some View {
        VStack {
            if let selectedVideoURL = selectedVideoURL {
                Text("Selected Video: \(selectedVideoURL.lastPathComponent)")
                
                Button("Compress and Upload Video") {
                    let compressedURL = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".mp4")
                    isUploading = true
                    
                    compressVideo(inputURL: selectedVideoURL, outputURL: compressedURL) { status in
                        if status == .completed {
                            uploadVideo(url: compressedURL) { result in
                                isUploading = false
                                switch result {
                                case .success:
                                    uploadStatus = "Upload Successful!"
                                case .failure(let error):
                                    uploadStatus = "Upload Failed: \(error.localizedDescription)"
                                }
                                // Cleanup the selected video URL as well
                                try? FileManager.default.removeItem(at: selectedVideoURL)
                                self.selectedVideoURL = nil
                            }
                        } else {
                            isUploading = false
                            uploadStatus = "Compression Failed"
                        }
                    }
                }
                .padding()
                
                Text(uploadStatus)
                    .padding()
            } else {
                Button("Select Video") {
                    isShowingVideoPicker = true
                }
                .padding()
            }
        }
        .sheet(isPresented: $isShowingVideoPicker) {
            VideoPickerView(selectedVideoURL: $selectedVideoURL)
        }
        .overlay(
            isUploading ? ProgressView("Uploading...").padding().background(Color.white).cornerRadius(10) : nil
        )
    }
}


