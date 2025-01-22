//
//  UIKitVideoPlayer.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/01/2025.
//

import SwiftUI
import Combine
import AVKit

struct UIKitVideoPlayer: UIViewControllerRepresentable {
    var url: URL
    var onVideoTap: (() -> Void)? // Optional callback for tap gesture

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        print("makeUIViewController111")
        let controller = AVPlayerViewController()
        controller.player = AnyPlayerModel.shared.player
        controller.showsPlaybackControls = false // Hide default controls
        controller.videoGravity = .resizeAspect
        
        if #available(iOS 18.0, *) {
            controller.allowsVideoFrameAnalysis = false
        }
        
        // Add tap gesture recognizer to the controller's view
        let tapGestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleTapGesture))
        controller.view.addGestureRecognizer(tapGestureRecognizer)
        
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        print("updateUIViewController111")
        // SwiftUI to UIKit
        // Update properties of the UIViewController based on the latest SwiftUI state.
        
        
        // No updates needed
        if context.coordinator.url != url {
            context.coordinator.url = url
            uiViewController.player = AnyPlayerModel.shared.player
        }
    }
    
    func makeCoordinator() -> Coordinator {
       Coordinator(url: url, onVideoTap: onVideoTap)
    }

    // Use the Coordinator to communicate events back to SwiftUI.
    // Implement any delegate methods or communication logic within the Coordinator.
    // UIKit to SwiftUI
    class Coordinator: NSObject {
        var url: URL
        let onVideoTap: (() -> Void)?

        init(url: URL, onVideoTap: (() -> Void)?) {
            self.url = url
            self.onVideoTap = onVideoTap
        }

        @objc func handleTapGesture() {
            onVideoTap?() // Call the closure if it is provided
        }
    }
}
