//
//  Ago.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/03/2023.
//

import SwiftUI

struct Ago: View {
    
    let date:Date
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    init(_ date:Date) {
        self.date = date
    }
    
    @State var agoText:String? = nil
    
    var body: some View {
        Text(agoText ?? date.agoString)
            .onReceive(timer) { _ in
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
