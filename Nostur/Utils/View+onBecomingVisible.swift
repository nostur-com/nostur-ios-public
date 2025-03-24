//
//  View+onBecomingVisible.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/09/2023.
//

import SwiftUI


public extension View {
    func onBecomingVisible(perform action: @escaping () -> Void) -> some View {
        modifier(BecomingVisible(action: action))
    }
}

private struct BecomingVisible: ViewModifier {
    
    @State var action: (() -> Void)?

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: VisibleKey.self,
                        // See discussion!
                        value: UIScreen.main.bounds.intersects(proxy.frame(in: .global))
                    )
                    .onPreferenceChange(VisibleKey.self) { isVisible in
                        guard isVisible, let action else { return }
                        action()
                        self.action = nil
                    }
            }
        }
    }

    struct VisibleKey: PreferenceKey {
        static let defaultValue: Bool = false
        static func reduce(value: inout Bool, nextValue: () -> Bool) { }
    }
}


public extension View {
    func onVisibilityChange(perform action: @escaping (Bool) -> Void) -> some View {
        modifier(VisibilityChange(action: action))
    }
}

private struct VisibilityChange: ViewModifier {
    
    @State var action: ((Bool) -> Void)?
    @State var isVisible: Bool = false

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: VisibleKey.self,
                        value: UIScreen.main.bounds.intersects(proxy.frame(in: .global))
                    )
                    .onPreferenceChange(VisibleKey.self) { isVisible in
                        guard let action else { return }
                        if isVisible != self.isVisible {
                            self.isVisible = isVisible
                            action(isVisible)
                        }
                    }
            }
        }
    }

    struct VisibleKey: PreferenceKey {
        static let defaultValue: Bool = false
        static func reduce(value: inout Bool, nextValue: () -> Bool) { }
    }
}
