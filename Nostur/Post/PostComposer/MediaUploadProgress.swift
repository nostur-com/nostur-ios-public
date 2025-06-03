//
//  MediaUploadProgress.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/10/2023.
//

import SwiftUI
import NostrEssentials

struct MediaUploadProgress: View {
    @ObservedObject public var uploader: Nip96Uploader
    
    var body: some View {
        VStack {
            ForEach(uploader.queued) { item in
                Bar(bag: item)
            }
        }
    }
}

struct Bar:View {
    @EnvironmentObject private var themes:Themes
    @EnvironmentObject private var dim:DIMENSIONS
    @ObservedObject public var bag:MediaRequestBag
    
    var body: some View {
        Group {
            switch bag.state {
            case .uploading(let percentage):
                themes.theme.secondaryBackground
                    .overlay(alignment: .leading) {
                        themes.theme.accent
                            .frame(width: ((dim.listWidth * Double(percentage ?? 0) / 100) * 0.7)) // to max 70%
                            .animation(.easeInOut, value: percentage)
                    }
                    .overlay {
                        Text(Int(Double(percentage ?? 0) * 0.7), format: .percent)
                    }
            case .processing(let percentage):
                themes.theme.secondaryBackground
                    .overlay(alignment: .leading) {
                        themes.theme.accent
                            .frame(width: (dim.listWidth * 0.7) + ((dim.listWidth * Double(percentage ?? 0) / 100) * 0.3)) // the remaining 30%
                            .animation(.easeInOut, value: percentage)
                    }
                    .overlay {
                        Text(Int(70) + Int(Double(percentage ?? 0) * 0.3), format: .percent)
                    }
            case .success(let url):
                Color.green
                    .overlay {
                        Text(url)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
            case .error(let message):
                Color.red
                    .overlay {
                        Text(message)
                    }
            case .initializing:
                themes.theme.background
                    .overlay {
                        Text(0, format: .percent)
                    }
            }
        }
        .frame(height: 34)
    }
}

#Preview {
    struct MediaUploadProgressPreview: View {
        @State var uploader = Nip96Uploader()
        @State var percentage:Int = 15
        var body: some View {
            VStack {
                MediaUploadProgress(uploader: uploader)
                
                Button("+15") {
                    uploader.queued.filter { !$0.finished }
                        .forEach { bag in
                            percentage += 15
                            if percentage >= 100 {
                                bag.state = .success("https://localhost")
                            }
                            else {
                                bag.state = .processing(percentage: percentage)
                            }
                        }
                }
            }
            .onAppear {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                
                let exampleCompleted = MediaRequestBag(apiUrl: URL(string: "http://localhost")!, mediaData: Data(), authorizationHeader: "")
                
                let completed = ###"{"status":"completed","message":"The requested file was found","processing_url":"","nip94_event":{"id":"","pubkey":"134743ca8ad0203b3657c20a6869e64f160ce48ae6388dc1f5ca67f346019ee7","created_at":"1697814847","kind":1063,"tags":[["url","https://nostrcheck.me/media/public/5ff2d652415296018c14f0b4c8e30364c066bf1cc88a44d3df7af4d80b9446da.mp4"],["m","video/mp4"],["x","32fa72a335c606d8c25c64b1351504b30a201f663a563b28db50b2a885dffec6"],["ox","5ff2d652415296018c14f0b4c8e30364c066bf1cc88a44d3df7af4d80b9446da"],["size","604573"],["dim","720x532"],["magnet","magnet:?xt=urn:btih:de3149ea451aeb026f98e5bc5c663e82f9edf596&dn=5aa722867e98e5464b0d22fc3762011ab01ff20da6a9ac5b6d71a04cc8937c14.webp&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337&tr=udp%3A%2F%2Fexplodie.org%3A6969&tr=udp%3A%2F%2Ftracker.empire-js.us%3A1337&tr=wss%3A%2F%2Ftracker.btorrent.xyz&tr=wss%3A%2F%2Ftracker.openwebtorrent.com&tr=wss%3A%2F%2Ftracker.webtorrent.dev"],["i",""],["blurhash",""]],"content":"","sig":""}}"###
                
                guard let completedResponse = try? decoder.decode(UploadResponse.self, from: completed.data(using: .utf8)!)
                else {
                    return
                }
                
                exampleCompleted.uploadResponse = completedResponse
                uploader.queued.append(exampleCompleted)
                
                let exampleProgress = MediaRequestBag(apiUrl: URL(string: "http://localhost")!, mediaData: Data(), authorizationHeader: "")
                let progress = ###"{"status":"processing","message":"Processing. Please check again later for updated status.","percentage":15,"nip94_event":{"id":"","pubkey":"134743ca8ad0203b3657c20a6869e64f160ce48ae6388dc1f5ca67f346019ee7","created_at":"1697814847","kind":1063,"tags":[["url","https://nostrcheck.me/media/public/5ff2d652415296018c14f0b4c8e30364c066bf1cc88a44d3df7af4d80b9446da.mp4"],["m","video/mp4"],["x","32fa72a335c606d8c25c64b1351504b30a201f663a563b28db50b2a885dffec6"],["ox","5ff2d652415296018c14f0b4c8e30364c066bf1cc88a44d3df7af4d80b9446da"],["size","604573"],["dim","720x532"],["magnet","magnet:?xt=urn:btih:de3149ea451aeb026f98e5bc5c663e82f9edf596&dn=5aa722867e98e5464b0d22fc3762011ab01ff20da6a9ac5b6d71a04cc8937c14.webp&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337&tr=udp%3A%2F%2Fexplodie.org%3A6969&tr=udp%3A%2F%2Ftracker.empire-js.us%3A1337&tr=wss%3A%2F%2Ftracker.btorrent.xyz&tr=wss%3A%2F%2Ftracker.openwebtorrent.com&tr=wss%3A%2F%2Ftracker.webtorrent.dev"],["i",""],["blurhash",""]],"content":"","sig":""}}"###
                
                guard let uploadResponseProgress = try? decoder.decode(UploadResponse.self, from: progress.data(using: .utf8)!)
                else {
                    return
                }
                
                exampleProgress.uploadResponse = uploadResponseProgress
                
                uploader.queued.append(exampleProgress)
            }
        }
    }
    return MediaUploadProgressPreview()
        .environmentObject(Themes.default)
        .environmentObject(DIMENSIONS())
}
