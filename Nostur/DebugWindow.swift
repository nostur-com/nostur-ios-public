//
//  DebugWindow.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/11/2023.
//

import SwiftUI

@available(iOS 16.0, *)
struct DebugWindow: View {
    @EnvironmentObject private var cp:ConnectionPool
    private var connections:[RelayConnection] {
        Array(cp.connections.values)
    }
    
    var body: some View {
        Table(connections) {
            TableColumn("") { c in
                Image(systemName: "circle.fill")
                    .foregroundColor(c.isConnected ? .green : .gray)
            }
            .width(min: 25, max: 45)
            
            TableColumn("Relay", value: \.url)
                .width(min: 100, max: 300)
            
            TableColumn("") { c in
                Image(systemName: "magnifyingglass.circle.fill")
                    .foregroundColor(c.relayData.search ? .blue : .clear)
            }
                .width(min: 25, max: 45)
            
            TableColumn("NWC") { c in
                Image(systemName: "creditcard")
                    .foregroundColor(c.isNWC ? .green : .clear)
            }
                .width(min: 25, max: 45)
            
            TableColumn("NC") { c in
                Image(systemName: "building.columns")
                    .foregroundColor(c.isNC ? .green : .clear)
            }
                .width(min: 25, max: 45)
        }
    }
}
