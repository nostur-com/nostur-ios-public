/**
*  SwiftUIScrollOffset
*  Copyright (c) Ciaran O'Brien 2024
*  MIT license, see LICENSE file for details
*/

import SwiftUI

internal extension View {
    func onValueChange<V>(_ value: V, action: @escaping (V, V) -> Void) -> some View
    where V : Equatable
    {
        modifier(OnValueChangeModifier(action: action, value: value))
    }
}


private struct OnValueChangeModifier<V>: ViewModifier
where V : Equatable
{
    var action: (V, V) -> Void
    var value: V
    
    func body(content: Content) -> some View {
        if #available(iOS 17, macOS 14, tvOS 17, visionOS 1, *) {
            content
                .onChange(of: value, action)
        } else {
            content
                .onChange(of: value) { [oldValue = value] newValue in
                    action(oldValue, newValue)
                }
        }
    }
}
