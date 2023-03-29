//
//  NewNoteButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/02/2023.
//

import SwiftUI

struct NewNoteButton: View {
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var nav:NavigationModel
    @Binding var showingNewNote:Bool
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    guard ns.account?.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
                    showingNewNote = true
                } label: {
                    ZStack {
                        Circle() // Transparent plug.circle looks weird - so make white here
                            .foregroundColor(Color(.white))
                            .frame(width: 45, height: 45)
                            .padding(30)
                        Image(systemName: "plus.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 45, height: 45)
                            .padding(30)
                    }
                }
                .accessibilityLabel("New post")
            }
            //                .offset(x:-30,y:-55)
        }
    }
}

struct NewNoteButton_Previews: PreviewProvider {
    
    @State static var showingNewNote = false
    @State static var noteCancellationId:UUID?
    
    static var previews: some View {
        NewNoteButton(showingNewNote: $showingNewNote)
            .sheet(isPresented: $showingNewNote) {
                NewNote(noteCancellationId: $noteCancellationId)
            }
            .withPreviewEnvironment()
    }
}
