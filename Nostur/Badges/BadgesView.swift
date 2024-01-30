//
//  BadgesView.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI

struct BadgesView: View {
    @EnvironmentObject private var themes: Themes
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
                    .background(themes.theme.listBackground)
            case "Received":
                BadgesReceivedContainer()
                    .background(themes.theme.listBackground)
            default:
                BadgesReceivedContainer()
                    .background(themes.theme.listBackground)
            }
            Spacer()
        }
        .background(themes.theme.listBackground)
        .nosturNavBgCompat(themes: themes)
    }
}

struct BadgesView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadBadges() }) {
            BadgesView()
        }
    }
}
