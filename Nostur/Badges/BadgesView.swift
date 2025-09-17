//
//  BadgesView.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI

struct BadgesView: View {
    @Environment(\.theme) private var theme
    @State var tab = "Issued"
    
    var body: some View {
        VStack {
            HStack {
                TabButton(action: {
                    tab = "Issued"
                }, title: String(localized:"Issued", comment: "Tab title of Issues badges"), selected: tab == "Issued")
                
                TabButton(action: {
                    tab = "Received"
                }, title: String(localized: "Received", comment: "Tab title of Received badges"), selected: tab == "Received")
            }
            switch tab {
            case "Issued":
                BadgesIssuedContainer()
                    .background(theme.listBackground)
            case "Received":
                BadgesReceivedContainer()
                    .background(theme.listBackground)
            default:
                BadgesReceivedContainer()
                    .background(theme.listBackground)
            }
            Spacer()
        }
        .background(theme.listBackground)
        .nosturNavBgCompat(theme: theme)
    }
}

struct BadgesView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadBadges() }) {
            BadgesView()
        }
    }
}
