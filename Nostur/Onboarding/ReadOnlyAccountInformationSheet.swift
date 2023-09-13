//
//  ReadOnlyAccountInformationSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/02/2023.
//

import SwiftUI

struct ReadOnlyAccountInformationSheet: View {
    @EnvironmentObject var theme:Theme
    @EnvironmentObject var ns:NosturState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Read-only mode\n", comment:"Heading for message read-only mode").font(.title)
                Text("You are using a read-only account.\n\nSwitch to another account or add the private key to fully use this account.", comment: "Message about read-only mode")
            
                AccountsSheet(withDismissButton:false)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        ns.readOnlyAccountSheetShown = false
                        dismiss()
                    }
                }
            })
            .padding(20)
            .background(theme.background)
        }
    }
}

struct ReadOnlyAccountInformationSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            ReadOnlyAccountInformationSheet()
        }
    }
}
