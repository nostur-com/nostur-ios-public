//
//  Ago.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/03/2023.
//

import SwiftUI

struct Ago: View, Equatable {
    
    static func == (lhs: Ago, rhs: Ago) -> Bool {
        lhs.agoText == rhs.agoText
    }
    
    private let date: Date
    @State var agoText: String
    
    public init(_ date: Date, agoText: String? = nil) {
        self.date = date
        _agoText = State(wrappedValue: agoText ?? date.agoString)
    }
    
    public init(_ timestamp: Int64) {
        self.date = Date(timeIntervalSince1970: Double(timestamp))
        _agoText = State(wrappedValue: date.agoString)
    }
    
    var body: some View {
        Text(verbatim: agoText)
            .onAppear {
                if date.agoString != agoText {
                    agoText = date.agoString
                }
            }
            .onReceive(AppState.shared.agoShouldUpdateSubject) { _ in
                if date.agoString != agoText {
                    agoText = date.agoString
                }
            }
    }
}

#Preview {
    VStack {
        Ago(Date.now - 45)
        Ago(Date.now - (2 * 60))
        Ago(Date.now - (2 * 3600))
        Ago(Date.now - (48 * 3600))
        Ago(Date.now - (148 * 3600))
        Ago(Date.now - (7 * 148 * 3600))
        Ago(Date.now - (28 * 148 * 3600))
        Ago(Date.now - (3 * 28 * 148 * 3600))
        Ago(Date.now - (8 * 28 * 148 * 3600))
    }
}
