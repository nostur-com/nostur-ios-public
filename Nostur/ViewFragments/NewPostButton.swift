//
//  NewPostButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/02/2023.
//

import SwiftUI

struct NewPostButton: View {
    @Environment(\.theme) private var theme
    private var action: () -> Void
    
    init(action: @escaping () -> Void) {
        self.action = action
    }
    
    var body: some View {
        Button {
            guard isFullAccount() else { showReadOnlyMessage(); return }
            action()
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

struct NewPostButton_Previews: PreviewProvider {
    
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
                NewPostButton(action: {
                    showingNewNote = true
                })
                .sheet(isPresented: $showingNewNote) {
                    ComposePost(onDismiss: { })
                }
                .buttonStyleGlass()
                .padding(30)
            }
        }
    }
}

