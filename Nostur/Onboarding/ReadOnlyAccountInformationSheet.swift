//
//  ReadOnlyAccountInformationSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/02/2023.
//

import SwiftUI

struct ReadOnlyAccountInformationSheet: View {
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            if UIDevice.current.userInterfaceIdiom == .pad {
                HStack {
                    Spacer()
                    Image(systemName: "xmark.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .padding(30)
                        .onTapGesture {
                            dismiss()
                        }
                }
            }
            Text("Read-only mode\n").font(.title)
            Text("You are using a read-only account.\n\nSwitch to another account or add the private key to fully use this account.")
        
            AccountsSheet(withDismissButton:false)
        }
        .padding(20)
    }
}

struct ReadOnlyAccountInformationSheet_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ReadOnlyAccountInformationSheet()
        }
        .withPreviewEnvironment()
    }
}
