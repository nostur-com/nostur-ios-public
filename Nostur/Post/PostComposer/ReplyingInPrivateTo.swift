//
//  ReplyingInPrivateTo.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/01/2026.
//

import SwiftUI

struct ReplyingInPrivateTo: View {
    @Environment(\.theme) private var theme
    @StateObject var nrContact: NRContact
    
    init(pubkey: String) {
        _nrContact = StateObject(wrappedValue: NRContact.instance(of: pubkey))
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 3) {
            Group {
                Text("Replying to **\(nrContact.anyName)**")
                    .foregroundColor(theme.secondary)
                    .lineLimit(1)
                
                Text("in private", comment: "Replying to xxx 'in private'").font(.system(size: 12.0))
                    .fontWeightBold()
                    .padding(.horizontal, 8)
                    .background(theme.accent.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding(.top, 3)
                    .layoutPriority(2)
                    .infoText("Your reply will be sent in private, only to \(nrContact.anyName). Uploading private videos or images is not yet supported.")
            }
            .font(.body)
            .fontWeightLight()
        }
        .contentShape(Rectangle())
    }
}

import NavigationBackport

#Preview("Replying to selector") {
    PreviewContainer({ pe in
        pe.loadContacts()
    }) {
        NBNavigationStack {
            ReplyingInPrivateTo(pubkey: "17538dc2a62769d09443f18c37cbe358fab5bbf981173542aa7c5ff171ed77c4")
        }
    }
}
