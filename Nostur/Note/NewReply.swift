//
//  NewReply.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

import SwiftUI

struct NewReply: View {
    var replyTo:Event
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var up:Unpublisher
    @State var noteText = ""
//    @Binding var noteCancellationId:UUID?
    
    enum FocusedField {
        case noteText
    }
    @FocusState private var focusedField: FocusedField?
    
    let newReplyEvent:NEvent
    
//    init(replyTo:Event, noteCancellationId:Binding<UUID?>) {
    init(replyTo:Event) {
        self.replyTo = replyTo
//        _noteCancellationId = noteCancellationId
        
        var newReply = NEvent(content: "")
        newReply.kind = .textNote
        
        let root = TagsHelpers(replyTo.tags()).replyToRootEtag()
        
        if (root != nil) { // ADD "ROOT" + "REPLY"
            let newRootTag = NEventTag(type: "e", otherInformation: root!.otherInformation[0], "", "root") // TODO RECOMMENDED RELAY HERE
            newReply.tags.append(newRootTag)
            
            let newReplyTag = NEventTag(type: "e", otherInformation: replyTo.id, "", "reply")
            
            newReply.tags.append(newReplyTag)
        }
        else { // ADD ONLY "ROOT"
            let newRootTag = NEventTag(type: "e", otherInformation: replyTo.id, "", "root")
            newReply.tags.append(newRootTag)
        }
        
        // ADD ALL "P" TAGS
        let existingPtags = TagsHelpers(replyTo.tags()).pTags()
        newReply.tags.append(contentsOf: existingPtags)
        
        // TODO: DEDUPLICATE P TAGS
        
        // ADD PUBKEY OF REPLYING TO EVENT
        let replyToPtag = NEventTag(type: "p", otherInformation: replyTo.pubkey)
        
        newReply.tags.append(replyToPtag)
        newReplyEvent = newReply
    }
    
    var body: some View {
        VStack {
            ScrollView {
                NoteRowView(event: replyTo, hideFooter: true)
                HStack {
                    NewReplyingToFragment(contact: replyTo.contact, pubkey: replyTo.pubkey)
                        .offset(x:80)
                    Spacer()
                }
                HStack(alignment: .top) {
                    ProfilePicView(pubkey: ns.account!.publicKey, account: ns.account!)
                        .padding(.horizontal, 10)
                    TextField(text: $noteText, prompt: Text("Enter your reply"), axis: .vertical) {
                        EmptyView()
                    }
                    .focused($focusedField, equals: .noteText)
                    .lineLimit(10...)
                }
                Spacer()
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    Button {
                        dismiss() // TODO: If wrote something, confirm cancellation
                    } label: {
                        Text("Cancel")
                    }
                    Spacer()
                    Button {
                        guard ns.account?.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
                        var nEvent = newReplyEvent
                        nEvent.content = noteText
                        
                        nEvent = applyMentionsNip08(nEvent)
                        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                            nEvent.content = replaceNsecWithHunter2(nEvent.content)
                        }
                        if let signedEvent = try? ns.signEvent(nEvent) {
//                            let _ = up.publish(signedEvent)
                            up.publishNow(signedEvent)
                            dismiss()
                        }
                    } label: {
                        Text("Post")
                    }
                    .buttonStyle(.borderedProminent)
                    .cornerRadius(20)
                }//.background(Color("BackgroundColor"))
            }
        }
        .padding(10)
        .onAppear {
            focusedField = .noteText
        }
    }
}

struct NewReplyingToFragment: View {

    var contact:Contact?
    var pubkey:String
    
    var body: some View {
        HStack(spacing:1) {
            Text("Replying to ")
                .foregroundColor(.secondary)
                .font(.system(size: 13))
                .fontWeight(.light)
            Group {
                if (contact != nil) {
                    Text("@\(contact!.username)")
                }
                else {
                    Text("@\(String(pubkey.prefix(5)))")
                }
            }.foregroundColor(.accentColor)
                .font(.system(size: 13))
                .fontWeight(.light)
        }
    }
}

struct NewReply_Previews: PreviewProvider {
    @State static var noteCancellationId:UUID?
    static var previews: some View {
        
        let event = PreviewFetcher.fetchEvent("c3a040feac185585f984147cdaf7a7ec5774b06db29ff25017c45026e470daeb")
        
        if (event != nil) {
            NewReply(replyTo:event!)
                .withPreviewEnvironment()
        }
    }
}
