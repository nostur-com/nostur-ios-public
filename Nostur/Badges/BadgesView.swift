//
//  BadgesView.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI

struct BadgesView: View {
    @State var tab = "Issued"
    
    var body: some View {
        VStack {
            HStack {
                TabButton(action: {
                        tab = "Issued"
                }, title: "Issued", selected: tab == "Issued")
                
                TabButton(action: {
                        tab = "Received"
                }, title: "Received", selected: tab == "Received")
            }
            switch tab {
                case "Issued":
                    BadgesIssuedContainer()
                case "Received":
                    BadgesReceivedContainer()
                default:
                    BadgesReceivedContainer()
            }
            Spacer()
        }
    }
}

struct BadgesView_Previews: PreviewProvider {
    static var previews: some View {
        BadgesView()
            .withPreviewEnvironment({ pe in pe.loadBadges() })
    }
}
