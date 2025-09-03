//
//  PostMenuBlockOptions.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/08/2025.
//

import SwiftUI

struct PostMenuBlockOptions: View {
    @Environment(\.theme) private var theme
    
    @ObservedObject var nrContact: NRContact
    public var rootDismiss:(() -> Void)? = nil

    var body: some View {
        Form {
            Section("") {
                Group {
                    Button("Block") { block(pubkey: nrContact.pubkey, name: nrContact.anyName); rootDismiss?() }
                    Button("Block for 1 hour") { temporaryBlock(pubkey: nrContact.pubkey, forHours: 1, name: nrContact.anyName); rootDismiss?() }
                    Button("Block for 4 hours") { temporaryBlock(pubkey: nrContact.pubkey, forHours: 4, name: nrContact.anyName); rootDismiss?() }
                    Button("Block for 8 hours") { temporaryBlock(pubkey: nrContact.pubkey, forHours: 8, name: nrContact.anyName); rootDismiss?() }
                    Button("Block for 1 day") { temporaryBlock(pubkey: nrContact.pubkey, forHours: 24, name: nrContact.anyName); rootDismiss?() }
                    Button("Block for 1 week") { temporaryBlock(pubkey: nrContact.pubkey, forHours: 24*7, name: nrContact.anyName); rootDismiss?() }
                    Button("Block for 1 month") { temporaryBlock(pubkey: nrContact.pubkey, forHours: 24*31, name: nrContact.anyName); rootDismiss?() }
                }
                .buttonStyle(.borderless)
                .foregroundColor(theme.accent)
            }
            .listRowBackground(theme.background)

        }
        
        .scrollContentBackgroundHidden()
        .background(theme.listBackground)
        
        .navigationTitle("Block \(nrContact.anyName)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    PostMenuBlockOptions(nrContact: NRContact.instance(of: ""))
}
