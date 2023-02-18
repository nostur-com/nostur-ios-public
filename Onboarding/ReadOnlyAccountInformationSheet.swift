//
//  ReadOnlyAccountInformationSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/02/2023.
//

import SwiftUI

struct ReadOnlyAccountInformationSheet: View {
    var body: some View {
        VStack {
            Text("Read-only mode\n").font(.title)
            Text("You are using a read-only account.\n\nSwitch to another account or add the private key to fully use this account.")
        
            AccountsSheet()
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
