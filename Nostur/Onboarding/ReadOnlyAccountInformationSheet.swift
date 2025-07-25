//
//  ReadOnlyAccountInformationSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/02/2023.
//

import SwiftUI
import NavigationBackport

struct ReadOnlyAccountInformationSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            Text("Read-only mode\n", comment:"Heading for message read-only mode").font(.title)
            Text("You are using a read-only account.\n\nSwitch to another account or add the private key to fully use this account.", comment: "Message about read-only mode")
        
            AccountsSheet(withDismissButton: false)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(content: {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    AppSheetsModel.shared.readOnlySheetVisible = false
                    dismiss()
                }
            }
        })
        .padding(20)
        .background(theme.listBackground)
    }
}

struct ReadOnlyAccountInformationSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            NBNavigationStack {
                ReadOnlyAccountInformationSheet()
            }
            .nbUseNavigationStack(.never)
        }
    }
}
