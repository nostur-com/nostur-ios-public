//
//  DownloadManager.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/07/2025.
//

import Foundation
import Combine

import Foundation
import Combine

class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    
    struct DownloadState {
        var progress: Double = 0
        var isDownloading = false
        var fileURL: URL? = nil
        var error: Error? = nil
        var subFolder = "tmp"
    }
    
    @Published private(set) var states: [URL: DownloadState] = [:]
    
    private var tasks: [URL: URLSessionDownloadTask] = [:]
    private var progressSubjects: [URL: PassthroughSubject<DownloadState, Never>] = [:]
    private let fileManager = FileManager.default
    
    func publisher(for url: URL, subFolder: String = "tmp") -> AnyPublisher<DownloadState, Never> {
        if let subject = progressSubjects[url] {
            return subject.eraseToAnyPublisher()
        } else {
            let subject = PassthroughSubject<DownloadState, Never>()
            progressSubjects[url] = subject
            subject.send(states[url] ?? DownloadState(subFolder: subFolder))
            return subject.eraseToAnyPublisher()
        }
    }
    
    func startDownload(from url: URL, subFolder: String = "tmp") {
        guard tasks[url] == nil else {
            L.a0.debug("Already downloading: \(url.lastPathComponent)")
            if let subject = progressSubjects[url], let state = states[url], let _ = state.fileURL {
                subject.send(states[url] ?? DownloadState(subFolder: subFolder))
                return
            }
            return
        }
        

        
        L.a0.debug("Starting download: \(url.lastPathComponent)")
        
        var state = states[url] ?? DownloadState(subFolder: subFolder)
        state.isDownloading = true
        state.error = nil
        states[url] = state
        progressSubjects[url]?.send(state)
        
        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                var state = self.states[url] ?? DownloadState(subFolder: subFolder)
                state.isDownloading = false

                if let error = error {
                    state.error = error
                    self.states[url] = state
                    self.progressSubjects[url]?.send(state)
                    return
                }
                
                guard let tempURL = tempURL else {
                    state.error = URLError(.badServerResponse)
                    self.states[url] = state
                    self.progressSubjects[url]?.send(state)
                    return
                }

                // Save to disk
                do {
                    let destination = self.localFileURL(for: url, folder: subFolder)
                    try? self.fileManager.removeItem(at: destination)
                    try? self.fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try self.fileManager.moveItem(at: tempURL, to: destination)
                    state.fileURL = destination
                    self.states[url] = state
                    self.progressSubjects[url]?.send(state)
                    L.a0.debug("Saved file: \(destination.path)")
                } catch {
                    state.error = error
                    self.states[url] = state
                    self.progressSubjects[url]?.send(state)
                }
            }
        }

        tasks[url] = task
        task.resume()
    }
    
    func localFileURL(for url: URL, folder: String = "tmp") -> URL {
        let filename = url.lastPathComponent
        let dir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent(folder).appendingPathComponent(filename)
    }
}


import Foundation
import Combine



import SwiftUI
import Combine

import SwiftUI
import Combine

struct AudioDownloadView: View {
    let url: URL

    @State private var state = DownloadManager.DownloadState()
    @State private var cancellable: AnyCancellable?

    var body: some View {
        VStack(spacing: 12) {
            if let fileURL = state.fileURL {
                Text("✅ Downloaded: \(fileURL.lastPathComponent)")
            } else if state.isDownloading {
                ProgressView()
                Text("Downloading...")
            } else if let error = state.error {
                Text("⚠️ Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
            }

            Button("Download") {
                DownloadManager.shared.startDownload(from: url)
            }
            .disabled(state.isDownloading || state.fileURL != nil)
        }
        .padding()
        .onAppear {
            print("Subscribed to: \(url.lastPathComponent)")

            cancellable = DownloadManager.shared
                .publisher(for: url)
                .receive(on: DispatchQueue.main)
                .sink { newState in
                    self.state = newState
                }
        }
        .onDisappear {
            cancellable?.cancel()
        }
    }
}






#Preview {
    VStack {
        AudioDownloadView(url: URL(string: "http://localhost:3000/6d99ec56d05e444c048bedb88bd21c7636c36b2ac855aa9867b688ba4c994cb1.m4a")!)
        AudioDownloadView(url: URL(string: "http://localhost:3000/6d99ec56d05e444c048bedb88bd21c7636c36b2ac855aa9867b688ba4c994cb1.m4a")!) // Reuses the same download
    }
}
