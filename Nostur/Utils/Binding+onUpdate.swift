//
//  Binding+onUpdate.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/03/2025.
//

import SwiftUI

extension Binding {
    func onUpdate(_ closure: @escaping (Value, Value) -> Void) -> Binding<Value> {
        Binding(get: {
            wrappedValue
        }, set: { newValue in
            let oldValue = wrappedValue
            wrappedValue = newValue
            closure(oldValue, newValue)
        })
    }
}
