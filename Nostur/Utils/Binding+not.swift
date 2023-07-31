//
//  Binding+not.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/07/2023.
//

import SwiftUI

extension Binding where Value == Bool {
    var not: Binding<Value> {
        Binding<Value>(
            get: { !self.wrappedValue },
            set: { self.wrappedValue = !$0 }
        )
    }
}
