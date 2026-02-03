//
//  SimultaneousGesture.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/01/2026.
//

import SwiftUI

/// FB18199844 - https://gist.github.com/tanmays/4213cc6f76241c5d4e4bdb6e53ce310d
///
/// Demo project to showcase a ScrollView bug in iOS 26.
/// Applying a `simultaneousGesture` to a view inside a ScrollView
/// prevents the ScrollView from scrolling as expected.
///
/// Expected behavior: Since we're using .simultaneousGesture, the scroll view
/// should also receive touch and be scrollable.
///
/// To reproduce, please run the project using Xcode 26.0 beta (17A5241e)
/// and simulator running iOS 26 (23A5260I).
///
/// Update: Apple suggested a workaround. Implemented using a SimultaneousLongPressGestureView.


// UIGestureRecognizerRepresentable
struct SimultaneousGesture: UIGestureRecognizerRepresentable {
    struct Value {
        let translation: CGSize
        let location: CGPoint
    }
    
    let onBegan: () -> Void
    let onChanged: (UILongPressGestureRecognizer) -> Void
    let onChangedWithTranslation: ((Value) -> Void)?
    let onEnded: () -> Void
    let onSwipeUp: () -> Void

    init(onBegan: @escaping () -> Void = {},
         onChanged: @escaping (UILongPressGestureRecognizer) -> Void = { _ in },
         onChangedWithTranslation: ((Value) -> Void)? = nil,
         onEnded: @escaping () -> Void = {},
         onSwipeUp: @escaping () -> Void = {}) {
        self.onBegan = onBegan
        self.onChanged = onChanged
        self.onChangedWithTranslation = onChangedWithTranslation
        self.onEnded = onEnded
        self.onSwipeUp = onSwipeUp
    }
    
    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let gestureRecognizer = UILongPressGestureRecognizer()
        
        // Configure the long press gesture
        gestureRecognizer.minimumPressDuration = 0.0 // Immediate recognition
        gestureRecognizer.allowableMovement = CGFloat.greatestFiniteMagnitude // Allow movement
        gestureRecognizer.delegate = context.coordinator
        
        return gestureRecognizer
    }
    
    func handleUIGestureRecognizerAction(_ gestureRecognizer: UILongPressGestureRecognizer, context: Context) {
        switch gestureRecognizer.state {
        case .began:
            let location = gestureRecognizer.location(in: gestureRecognizer.view)
            context.coordinator.gestureBeganAt(location: location)
            onBegan()
            onChanged(gestureRecognizer)
            if let onChangedWithTranslation = onChangedWithTranslation {
                let value = Value(translation: .zero, location: location)
                onChangedWithTranslation(value)
            }
        case .changed:
            let location = gestureRecognizer.location(in: gestureRecognizer.view)
            context.coordinator.gestureChangedTo(location: location)
            onChanged(gestureRecognizer)
            if let onChangedWithTranslation = onChangedWithTranslation,
               let translation = context.coordinator.currentTranslation {
                let value = Value(translation: translation, location: location)
                onChangedWithTranslation(value)
            }
        case .ended, .cancelled:
            context.coordinator.gestureEnded()
            onEnded()
        default:
            break
        }
    }
    
    func updateUIGestureRecognizer(_ gestureRecognizer: UILongPressGestureRecognizer, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(onSwipeUp: onSwipeUp)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onSwipeUp: () -> Void
        private var initialLocation: CGPoint?
        private(set) var currentTranslation: CGSize?
        
        init(onSwipeUp: @escaping () -> Void) {
            self.onSwipeUp = onSwipeUp
            super.init()
        }
        
        func gestureBeganAt(location: CGPoint) {
            initialLocation = location
            currentTranslation = .zero
        }
        
        func gestureChangedTo(location: CGPoint) {
            guard let initial = initialLocation else { return }
            
            let horizontalMovement = location.x - initial.x
            let verticalMovement = location.y - initial.y
            
            currentTranslation = CGSize(width: horizontalMovement, height: verticalMovement)
            
            // Detect upward swipe: vertical movement > 50 points, mostly vertical
            if -verticalMovement > 50 && -verticalMovement > abs(horizontalMovement) * 2 {
                onSwipeUp()
                initialLocation = nil // Reset to avoid multiple triggers
            }
        }
        
        func gestureEnded() {
            initialLocation = nil
            currentTranslation = nil
        }
        
        // Key method for simultaneous recognition with ScrollView
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        // Optional: Add conditions to fail early if needed
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // Add any conditions here to fail early if the gesture is invalid
            return true
        }
    }
}
