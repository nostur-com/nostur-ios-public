//
//  NXListRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/10/2025.
//

import SwiftUI

// A List Row that detects top offset, handles (actual) appear on screen (not normal appear in view),
// triggers onAppearOnce (only once!) when row is partially visible
// Needs .withContainerTopOffsetEnvironmentKey() on a container view, only works when container is maximally at the top of screen
// if other views need to be above this view, they need to be in the top safeArea (toolbar etc) or offset calculation will be broken
struct NXListRow<Content: View>: View {
    @Environment(\.containerTopOffset) var topOffset
    private let content: Content
    @State private var onAppearOnce: (() -> Bool)?
    
    init(@ViewBuilder _ content: () -> Content, onAppearOnce: (() -> Bool)? = nil) {
        self.content = content()
        _onAppearOnce = State(wrappedValue: onAppearOnce)
    }
    
    var body: some View {
        self.content
            .modifier { // From iOS 16+ onGeometryChange should be more performant than the old GeometryReader method
                if #available(iOS 16.0, *) {
                    $0.onGeometryChange(for: Bool.self) { proxy in
                        guard onAppearOnce != nil else { return false }
                        let frame = proxy.frame(in: .global)
                        return (frame.minY - topOffset) > -25
                        
                    } action: { isVisible in
                        guard onAppearOnce != nil && isVisible else { return }
                        if onAppearOnce?() ?? false { // Set to nil ONLY if it actually ran (based on return value) (true means it ran)
                            onAppearOnce = nil
                        }
                    }
                }
                else {
                    $0.overlay { // Old GeometryReader method
                        if onAppearOnce != nil {
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: ListRowTopOffsetKey.self, value: proxy.frame(in: .global).minY - topOffset)
                            }
                            .onPreferenceChange(ListRowTopOffsetKey.self) { offset in
                                if offset >= -25 {
                                    if onAppearOnce?() ?? false { // Set to nil ONLY if it actually ran (based on return value) (true means it ran)
                                        onAppearOnce = nil
                                    }
                                }
                            }
                        }
                    }
                }
            }
    }
}

struct WithTopOffsetEnvironmentKeyViewModifier: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geo in
            content
                .environment(\.containerTopOffset, geo.safeAreaInsets.top == 0 ? geo.frame(in: .global).minY : geo.safeAreaInsets.top)
        }
    }
}

extension View {
    func withContainerTopOffsetEnvironmentKey() -> some View {
        modifier(WithTopOffsetEnvironmentKeyViewModifier())
    }
}

private struct ContainerTopOffSetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var containerTopOffset: CGFloat { // Container view top offset including safeArea.top handling, apply with .withContainerTopOffsetEnvironmentKey() on parent of a NXListRow
        get { self[ContainerTopOffSetKey.self] }
        set { self[ContainerTopOffSetKey.self] = newValue }
    }
}

struct ListRowTopOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = -10000
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { }
}

// See usage in ScrollOffsetTest.swift and NXFeed.swift
