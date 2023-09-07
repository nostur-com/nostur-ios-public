//
//  Ago.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/03/2023.
//

import SwiftUI

struct Ago: View { //, Equatable {
    
//    static func == (lhs: Ago, rhs: Ago) -> Bool {
//        lhs.agoText == rhs.agoText
//    }
//    
    let date:Date
    
    init(_ date:Date, agoText:String? = nil) {
        self.date = date
        self.agoText = agoText // Shaving miliseconds, so we dont have to .agoString again, already did it when creating NRPost()
    }
    
    init(_ timestamp:Int64) {
        self.date = Date(timeIntervalSince1970: Double(timestamp))
    }
    
    @State var agoText:String? = nil
    
    var body: some View {
        Text(verbatim: (agoText ?? date.agoString))
            .onReceive(NosturState.shared.agoTimer) { _ in
                if date.agoString != agoText {
                    agoText = date.agoString
                }
            }
    }
}

struct Ago_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Ago(Date.now - 45)
            Ago(Date.now - (2 * 60))
            Ago(Date.now - (2 * 3600))
            Ago(Date.now - (48 * 3600))
            Ago(Date.now - (148 * 3600))
        }
    }
}
