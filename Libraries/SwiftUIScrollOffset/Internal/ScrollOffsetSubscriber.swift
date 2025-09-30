/**
*  SwiftUIScrollOffset
*  Copyright (c) Ciaran O'Brien 2024
*  MIT license, see LICENSE file for details
*/

import SwiftUI
import SwiftUIIntrospect
@_spi(Advanced) import SwiftUIIntrospect

@MainActor
internal struct ScrollOffsetSubscriber: ViewModifier {
    @State private var automaticID = UUID()
    
    var scrollOffsetID: ScrollOffsetID
    
    func body(content: Content) -> some View {
        content
            .environment(\.scrollPublisherID, id)
            .modifier(ScrollOffsetIntrospectionModifier(id: id))
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .hidden()
                        .onAppear {
                            ScrollSubscriptionStore.shared.updateOffset(for: id)
                        }
                        .onValueChange(geometry.frame(in: .global)) { _, _ in
                            ScrollSubscriptionStore.shared.updateOffset(for: id)
                        }
                }
            )
            .onValueChange(id) { oldID, newID in
                ScrollSubscriptionStore.shared.updateSubscription(from: oldID, to: newID)
            }
            .onDisappear {
                ScrollSubscriptionStore.shared.unsubscribe(id: id)
            }
    }
    
    private var id: AnyHashable {
        scrollOffsetID.id ?? AnyHashable(automaticID)
    }
}


private struct ScrollOffsetIntrospectionModifier: ViewModifier {
    var id: AnyHashable
    
    #if canImport(UIKit)
    #if os(tvOS)
    func body(content: Content) -> some View {
        content
            .introspect(.scrollView, on: .tvOS(.v15...)) { scrollView in
                ScrollSubscriptionStore.shared.subscribe(id: id, scrollView: scrollView)
            }
    }
    #elseif os(visionOS)
    func body(content: Content) -> some View {
        content
            .introspect(.scrollView, on: .visionOS(.v1, .v2...)) { scrollView in
                ScrollSubscriptionStore.shared.subscribe(id: id, scrollView: scrollView)
            }
    }
    #else
    func body(content: Content) -> some View {
        content
            .introspect(.scrollView, on: .iOS(.v15...)) { scrollView in
                ScrollSubscriptionStore.shared.subscribe(id: id, scrollView: scrollView)
            }
    }
    #endif
    #elseif canImport(AppKit)
    func body(content: Content) -> some View {
        content
            .introspect(.scrollView, on: .macOS(.v12...)) { scrollView in
                ScrollSubscriptionStore.shared.subscribe(id: id, scrollView: scrollView)
            }
    }
    #else
    func body(content: Content) -> some View {
        content
    }
    #endif
}
