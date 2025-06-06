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

struct SizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
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
    
    var label:String? = nil
    var alignment:Alignment
    @State var actualSize:CGSize? = nil
    
    var horizontalAlignment: HorizontalAlignment {
        switch alignment {
        case .bottomLeading, .leading, .topLeading:
            .leading
        case .bottomTrailing, .trailing, .topTrailing:
            .trailing
        default:
            .center
        }
    }
    
    func body(content: Content) -> some View {
    #if DEBUG
        if 1 == 2 {
            content
                .readSize { size in
                    actualSize = size
                }
                .overlay(alignment: alignment) {
                    if let actualSize {
                        VStack(alignment: horizontalAlignment) {
                            if let label {
                                Text(label)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .background(.brown)
                                    .fontWeightBold()
                            }
                            Text(actualSize.debugDescription)
                                .font(.caption)
                                .foregroundColor(.white)
                                .background(.black)
                                .fontWeightBold()
                        }
                    }
                }
        }
        else {
            content
        }
    #else
        content
    #endif
    }
}




struct SizeModifier: ViewModifier {
    private var sizeView: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
        }
    }

    func body(content: Content) -> some View {
        content.overlay(sizeView) // .background does not always work (gives 0,0), but overlay does work??)
    }
}

struct HorizontallyScrollingView: ViewModifier {
    var maxWidth: CGFloat
    
    func body(content: Content) -> some View {
        ScrollView(.horizontal) {
            content
        }
        .frame(maxWidth: maxWidth)
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
    func debugDimensions(_ label:String? = nil, alignment:Alignment = .bottomTrailing) -> some View {
        modifier(DebugDimensions(label: label, alignment: alignment))
    }
    
    func hScroll(maxWidth: CGFloat) -> some View {
        modifier(HorizontallyScrollingView(maxWidth: maxWidth))
    }
}
