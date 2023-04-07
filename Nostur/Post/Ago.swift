//
//  Ago.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/03/2023.
//

import SwiftUI
import Compactor

struct Ago: View, Equatable {
    
    static func == (lhs: Ago, rhs: Ago) -> Bool {
        lhs.date == rhs.date
    }
    
    let date:Date
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @State var agoText = ""
    
    init(_ date:Date) {
        self.date = date
    }
    
    var ago: String {
        get {
            let f = TimeCompactor(ifZero: nil, style: .short, roundSmallToWhole: true)
            return f.string(from: Double(Date.now.timeIntervalSince(date)) as NSNumber)!
        }
    }
    
    var body: some View {
        Text(agoText)
            .onAppear {
                agoText = ago
            }
            .onReceive(timer) { _ in
                if ago != agoText {
                    agoText = ago
                }
            }
    }
}

struct Ago_Previews: PreviewProvider {
    static var previews: some View {
        Ago(Date.now - 45)
    }
}
