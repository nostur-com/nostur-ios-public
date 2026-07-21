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
    let nrPost: NRPost
    let vm: NXColumnViewModel
    
    @Environment(\.containerTopOffset) private var containerTopOffset
    @ViewBuilder var content: Content
    @State private var didAppearOnce = false
    
    var body: some View {
        content
            .modifier { // From iOS 16+ onGeometryChange should be more performant than the old GeometryReader method
                if #available(iOS 16.0, *) {
                    $0.onGeometryChange(for: Bool.self) { proxy in
                        guard !didAppearOnce else { return false }
                        let frame = proxy.frame(in: .global)
                        return (frame.minY - containerTopOffset) > -25
                        
                    } action: { isVisible in
                        guard !didAppearOnce && isVisible else { return }
                        if vm.handleAppearOnce(nrPost: nrPost) {
                            didAppearOnce = true
                        }
                    }
                }
                else {
                    $0.overlay { // Old GeometryReader method
                        if !didAppearOnce {
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: ListRowTopOffsetKey.self, value: proxy.frame(in: .global).minY - containerTopOffset)
                            }
                            .onPreferenceChange(ListRowTopOffsetKey.self) { offset in
                                if offset >= -25 {
                                    if vm.handleAppearOnce(nrPost: nrPost) {
                                        didAppearOnce = true
                                    }
                                }
                            }
                        }
                    }
                }
            }
    }
}

/// Measures top offset without wrapping the scroll view in a GeometryReader (which breaks
/// system tab-bar minimize / scroll-edge linking on iOS 26).
struct WithTopOffsetEnvironmentKeyViewModifier: ViewModifier {
    @State private var topOffset: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .environment(\.containerTopOffset, topOffset)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: ContainerTopOffsetPreferenceKey.self,
                            value: geo.safeAreaInsets.top == 0 ? geo.frame(in: .global).minY : geo.safeAreaInsets.top
                        )
                }
            }
            .onPreferenceChange(ContainerTopOffsetPreferenceKey.self) { topOffset = $0 }
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

private struct ContainerTopOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
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
