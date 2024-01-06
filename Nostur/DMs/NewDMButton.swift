//
//  NewDMButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/03/2023.
//

import SwiftUI

struct NewDMButton: View {

    @Binding var showingNewDM:Bool
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    guard isFullAccount() else { showReadOnlyMessage(); return }
                    showingNewDM = true
                } label: {
                    ZStack {
                        Circle()
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
        }
    }
}

import NavigationBackport

struct NewDMButton_Previews: PreviewProvider {
    @State static var showingNewDM = false
    static var previews: some View {
        PreviewContainer {
            NBNavigationStack {
                NewDMButton(showingNewDM: $showingNewDM)
            }
        }
    }
}
