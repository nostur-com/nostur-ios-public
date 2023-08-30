//
//  View+centered.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/03/2023.
//

import SwiftUI

struct CenteredView: ViewModifier {
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 0) {
                Spacer()
                content
                Spacer()
            }
            Spacer()
        }
    }
}

struct VerticallyCenteredView: ViewModifier {
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            Spacer()
            content
            Spacer()
        }
    }
}

struct HorizontallyCenteredView: ViewModifier {
    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            Spacer()
            content
            Spacer()
        }
    }
}

extension View {
  func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
    overlay(
      GeometryReader { geometryProxy in
        Color.clear
          .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
      }
    )
    .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
  }
}

struct DebugDimensions: ViewModifier {
    
    @State var actualSize:CGSize? = nil
    
    func body(content: Content) -> some View {
        content
            .readSize { size in
                actualSize = size
            }
            .overlay(alignment: .bottomTrailing) {
                if let actualSize {
                    Text(actualSize.debugDescription)
                        .font(.caption)
                        .foregroundColor(.white)
                        .background(.black)
                        .fontWeight(.bold)
                }
            }
    }
}

extension View {
    func centered() -> some View {
        modifier(CenteredView())
    }
    func vCentered() -> some View {
        modifier(VerticallyCenteredView())
    }
    func hCentered() -> some View {
        modifier(HorizontallyCenteredView())
    }
    func debugDimensions() -> some View {
        modifier(DebugDimensions())
    }
}
