//
//  MusicOrVideo.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/10/2023.
//

import SwiftUI

struct MusicOrVideo: View {
    public var url:URL
    @Binding public var isPlaying:Bool
    @Binding public var isMuted:Bool
    @Binding public var didStart:Bool
    public var fullWidth:Bool
    public var contentPadding:CGFloat
    public var videoWidth:CGFloat
    
    enum LoadingState {
        case initializing
        case loading
        case video
        case audio
        case unknown
        case timeout
    }
    
    static let aspect:CGFloat = 16/9
    
    @State private var state:LoadingState = .initializing
    
    var body: some View {
        switch state {
        case .initializing, .loading:
            ProgressView()
                .onAppear {
                    Task.detached {
                        fetchStreamType(url: url) { result in
                            do {
                                let streamType = try result.get()
                                DispatchQueue.main.async {
                                    if streamType == .video {
                                        self.state = .video
                                    }
                                    else {
                                        self.state = .audio
                                    }
                                }
                            }
                            catch {
                                self.state = .video
                            }
                        }
                        
                        do {
                            try await Task.sleep(
                                until: .now + .seconds(8.0),
                                tolerance: .seconds(2),
                                clock: .continuous
                            )
                            if self.state != .video && self.state != .audio {
                                self.state = .timeout
                            }
                        } catch { }
                    }
                }
        case .video, .unknown:
            StreamurRepresentable(url: url, isPlaying: $isPlaying, isMuted: $isMuted)
                .frame(height: videoWidth / Self.aspect)
                .padding(.horizontal, fullWidth ? -contentPadding : 0)
                .overlay {
                    if !didStart {
                        Color.black
                            .overlay {
                                Button(action: {
                                    isPlaying = true
                                    didStart = true
                                    sendNotification(.startPlayingVideo, url.absoluteString)
                                }) {
                                    Image(systemName:"play.circle")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 45, height: 45)
                                        .centered()
                                        .contentShape(Rectangle())
                                }
                            }
                    }
                }
                .onAppear {
                    isMuted = false
                }
                .onReceive(receiveNotification(.startPlayingVideo)) { notification in
                    let otherUrl = notification.object as! String
                    if url.absoluteString != otherUrl {
                        isPlaying = false
                        isMuted = true
                    }
                }
        case .audio:
            StreamurRepresentable(url: url, isPlaying: $isPlaying, isMuted: $isMuted)
                .frame(height: 75.0)
                .padding(.horizontal, fullWidth ? -contentPadding : 0)
                .overlay {
                    if !didStart {
                        Color.black
                            .overlay {
                                Button(action: {
                                    isPlaying = true
                                    didStart = true
                                    sendNotification(.startPlayingVideo, url.absoluteString)
                                }) {
                                    Image(systemName:"play.circle")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 45, height: 45)
                                        .centered()
                                        .contentShape(Rectangle())
                                }
                            }
                    }
                }
                .overlay(alignment:.topTrailing) {
                    Image(systemName: "music.note")
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                        .padding(3)
                        .background(.black)
                        .padding(5)
                }
                .onAppear {
                    isMuted = false
                }
                .onReceive(receiveNotification(.startPlayingVideo)) { notification in
                    let otherUrl = notification.object as! String
                    if url.absoluteString != otherUrl {
                        isPlaying = false
                        isMuted = true
                    }
                }
        case .timeout:
            Text("Unable to load stream")
        }
    }
}


// Fetch and parse meta og tags
func fetchStreamType(url: URL, completion: @escaping (Result<StreamType, Error>) -> Void) {
    // if youtube, use https://youtube.com/oembed?url= to fetch metadata (less than 1 KB, vs ~800 KB regular youtube page)
    let request = URLRequest(url: url)
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        guard let data = data, error == nil else {
            completion(.failure(error!))
            return
        }
        guard let content = String(data: data, encoding: .utf8) else {
            completion(.failure(NSError(domain: "Invalid", code: 0, userInfo: nil)))
            return
        }
        
        DispatchQueue.global().async {
            completion(.success(detectStreamType(content)))
        }
    }
    task.resume()
}

public enum StreamType {
    case video
    case audio
    case unknown
}

func detectStreamType(_ content:String) -> StreamType {
    let content = content.prefix(400)
    if content.contains("RESOLUTION=") {
        return .video
    }
    else if content.contains("FRAME-RATE=") {
        return .video
    }
    return .unknown // probably audio
}

