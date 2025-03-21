//
//  NewNoteButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/02/2023.
//

import SwiftUI

struct NewNoteButton: View {
    @EnvironmentObject private var themes:Themes
    @Binding var showingNewNote:Bool
    
    var body: some View {
        Button {
            guard isFullAccount() else { showReadOnlyMessage(); return }
            showingNewNote = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.white, themes.theme.accent)
                .frame(width: 45, height: 45)
        }
        .accessibilityLabel(String(localized:"New post", comment: "Button to create a new post"))
    }
}

struct NewNoteButton_Previews: PreviewProvider {
    
    @State static var showingNewNote = false
    
    static var previews: some View {
        PreviewContainer {
            NewNoteButton(showingNewNote: $showingNewNote)
                .sheet(isPresented: $showingNewNote) {
                    ComposePostCompat(onDismiss: { })
                }
        }
    }
}
