//
//  NewNoteButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/02/2023.
//

import SwiftUI

struct NewNoteButton: View {
    @Environment(\.theme) private var theme
    @Binding var showingNewNote:Bool
    
    var body: some View {
        
        Button {
            guard isFullAccount() else { showReadOnlyMessage(); return }
            showingNewNote = true
        } label: {
            Label(String(localized:"New post", comment: "Button to create a new post"), systemImage: "plus")
                .font(.title)
                .fontWeightBold()
                .labelStyle(.iconOnly)
                .padding(.vertical, 5)
        }
        .buttonStyleGlass()
        .tint(theme.accent)
        .buttonBorderShape(.roundedRectangle(radius: 45))
    }
}

struct NewNoteButton_Previews: PreviewProvider {
    
    @State static var showingNewNote = false
    
    static var previews: some View {
        PreviewContainer {
            ScrollView {
                VStack {
                    Text("Testing liquid glass, testing\nTesting liquid glass, testing\n")
                        .foregroundStyle(Color(.secondaryLabel))
                    Text("Testing liquid glass, testing\nTesting liquid glass, testing\n")
                        .foregroundStyle(Color(.secondaryLabel))
                    Text("Testing liquid glass, testing\nTesting liquid glass, testing\n")
                        .foregroundStyle(Color.red)
                    Text("Testing liquid glass, testing\nTesting liquid glass, testing\n")
                        .foregroundStyle(Color.red)
                    Text("Testing liquid glass, testing\nTesting liquid glass, testing\n")
                        .foregroundStyle(Color.random)
                    Text("Testing liquid glass, testing\nTesting liquid glass, testing\n")
                        .foregroundStyle(Color.random)
                    Text("Testing liquid glass, testing\nTesting liquid glass, testing\n")
                        .foregroundStyle(Color.random)
                    Text("Testing liquid glass, testing\nTesting liquid glass, testing\n")
                        .foregroundStyle(Color(.secondaryLabel))
                    Text("Testing liquid glass, testing\nTesting liquid glass, testing\n")
                        .foregroundStyle(Color(.secondaryLabel))
                    Text("Testing liquid glass, testing\nTesting liquid glass, testing\n")
                        .foregroundStyle(Color.red)
                    Text("Testing liquid glass, testing\nTesting liquid glass, testing\n")
                        .foregroundStyle(Color.red)
                    Text("Testing liquid glass, testing\nTesting liquid glass, testing\n")
                        .foregroundStyle(Color.random)
                    Text("Testing liquid glass, testing\nTesting liquid glass, testing\n")
                        .foregroundStyle(Color.random)
                    Text("Testing liquid glass, testing\nTesting liquid glass, testing\n")
                        .foregroundStyle(Color.random)
                    Spacer()
                }
                .font(.title2)
            }
            .overlay {
                NewNoteButton(showingNewNote: $showingNewNote)
                    .sheet(isPresented: $showingNewNote) {
                        ComposePost(onDismiss: { })
                    }
                    .buttonStyleGlass()
                    .padding(30)
            }
        }
    }
}

