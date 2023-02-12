//
//  NewNote.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

import SwiftUI

struct NewNote: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var up:Unpublisher
    @State var noteText = ""
    @Binding var noteCancellationId:UUID?
    
    enum FocusedField {
        case noteText
    }
    @FocusState private var focusedField: FocusedField?
    
    var body: some View {
        VStack {
            HStack {
                Button {
                    dismiss() // TODO: If wrote something, confirm cancellation
                    
                } label: {
                    Text("Cancel")
                }
                Spacer()
                Button {
                    let nEvent = NEvent(content: noteText)
                    if let signedEvent = try? ns.signEvent(nEvent) {
                        noteCancellationId = up.publish(signedEvent)
                        dismiss()
                    }
                } label: {
                    Text("Post")
                }
                .buttonStyle(.borderedProminent)
                .cornerRadius(20)
            }
            
            HStack {
                ProfilePicView(pubkey: ns.activeAccountPublicKey, account: ns.account!)
                TextField(text: $noteText, prompt: Text("What's happening?")) {
                    EmptyView()
                }
                .focused($focusedField, equals: .noteText)
            }
            
            Spacer()
        }
        .padding(10)
        .onAppear {
            focusedField = .noteText
        }
    }
}

struct NewNote_Previews: PreviewProvider {
    @State static var noteCancellationId:UUID?
    static var previews: some View {
        NewNote(noteCancellationId: $noteCancellationId)
            .withPreviewEnvironment()
    }
}
