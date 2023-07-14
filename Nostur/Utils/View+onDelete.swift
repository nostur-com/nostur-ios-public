//
//  View+onDelete.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/05/2023.
//

import Foundation

import SwiftUI
// Deleting rows inside LazyVStack and ForEach in SwiftUI
// https://stackoverflow.com/a/75841800
struct Delete: ViewModifier {

    let tint:Color
    let label:String
    let icon:String
    let action: () -> Void
    
    @State var offset: CGSize = .zero
    @State var initialOffset: CGSize = .zero
    @State var contentWidth: CGFloat = 0.0
    @State var willDeleteIfReleased = false
   
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    ZStack {
                        Rectangle()
                            .foregroundColor(tint)
                        Label(label, systemImage: icon)
                            .foregroundColor(.white)
                            .layoutPriority(-1)
                            .lineLimit(1)
                    }
                    .frame(width: -offset.width)
                    .clipShape(Rectangle() )
                    .offset(x: geometry.size.width)
                    .onAppear {
                        contentWidth = geometry.size.width
                    }
                    .gesture(
                        TapGesture()
                            .onEnded {
                                delete()
                            }
                    )
                }
            )
            .offset(x: offset.width, y: 0)
            .gesture (
                DragGesture()
                    .onChanged { gesture in
                        if gesture.translation.width + initialOffset.width <= 0 {
                            self.offset.width = gesture.translation.width + initialOffset.width
                        }
                        if self.offset.width < -deletionDistance && !willDeleteIfReleased {
                            hapticFeedback()
                            willDeleteIfReleased.toggle()
                        } else if offset.width > -deletionDistance && willDeleteIfReleased {
                            hapticFeedback()
                            willDeleteIfReleased.toggle()
                        }
                    }
                    .onEnded { _ in
                        if offset.width < -deletionDistance {
                            delete()
                        } else if offset.width < -halfDeletionDistance {
                            offset.width = -tappableDeletionWidth
                            initialOffset.width = -tappableDeletionWidth
                        } else {
                            offset = .zero
                            initialOffset = .zero
                        }
                    }
            )
            .animation(.interactiveSpring(), value: offset)
    }
    
    private func delete() {
        //offset.width = -contentWidth
        
        offset = .zero
        initialOffset = .zero
        action()
    }
    
    private func hapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    //MARK: Constants
    
    let deletionDistance = CGFloat(200)
    let halfDeletionDistance = CGFloat(50)
    let tappableDeletionWidth = CGFloat(100)
    
    
}

extension View {
    
    func onDelete(perform action: @escaping () -> Void) -> some View {
        self.modifier(Delete(tint:Color.red, label:"Delete", icon:"trash", action: action))
    }
    
    func onSwipe(tint:Color = Color.red, label:String, icon:String, perform action: @escaping () -> Void) -> some View {
        self.modifier(Delete(tint:tint, label:label, icon:icon, action: action))
    }
}
