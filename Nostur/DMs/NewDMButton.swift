//
//  NewDMButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/03/2023.
//

import SwiftUI

struct NewDMButton: View {
    @EnvironmentObject var ns:NosturState
     
    @Binding var showingNewDM:Bool
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    guard ns.account?.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
                    showingNewDM = true
                } label: {
                    ZStack {
                        Circle() // Transparent plug.circle looks weird - so make white here
                            .foregroundColor(Color(.white))
                            .frame(width: 45, height: 30)
                            .padding(30)
                        Image(systemName: "plus.message.fill")
                            .resizable()
                            .scaleEffect(x: -1)
                            .scaledToFit()
                            .frame(width: 45, height: 45)
                            .padding(30)
                    }
                }
            }
            //                .offset(x:-30,y:-55)
        }
    }
}

struct NewDMButton_Previews: PreviewProvider {
    @State static var showingNewDM = false
    static var previews: some View {
        NavigationStack {
            NewDMButton(showingNewDM: $showingNewDM)
        }
        .withPreviewEnvironment()
    }
}
