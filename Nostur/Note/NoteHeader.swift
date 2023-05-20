//
//  NoteHeader.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/02/2023.
//

import SwiftUI

struct NoteHeader: View {
     
    @ObservedObject var event:Event
    var singleLine:Bool = true
    var hideEmojis:Bool
    
    var showUsername:Bool { // show (user)name if (user)name is different from display name
        guard let contact = event.contact else { return false }
        guard !contact.username.isEmpty else { return false }
        guard contact.username.lowercased() != contact.anyName.lowercased() else { return false }
        return true
    }
    
    init(event:Event, singleLine:Bool = true) {
        self.event = event
        self.singleLine = singleLine
        self.hideEmojis = SettingsStore.shared.hideEmojisInNames
    }
    
    var body: some View {
        //        NavigationLink(value: event, label: {
        
        VStack(alignment: .leading, spacing:0) { // Name + menu "replying to"
            HStack(spacing:5) {
                Group {
                    if (event.contact != nil) {
                        Text(event.contact!.anyName) // Name
                            .foregroundColor(.primary)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .layoutPriority(2)
                    }
                    else {
                        Text("...") // Name
                            .foregroundColor(.primary)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .redacted(reason: .placeholder)
                    }
                    
                    if (event.contact?.nip05veried ?? false) {
                        Image(systemName: "checkmark.seal.fill")
//                            .font(.system(size: 14))
                            .foregroundColor(Color("AccentColor"))
                            .layoutPriority(3)
                    }
                    
                    if (singleLine) {
                        Group {
                            if showUsername {
                                Text("@\(event.contact?.username ?? "...")").layoutPriority(1)
                                Text(" · ") //
                            }
                            Ago(event.date).layoutPriority(1)
                        }
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    }
                }
                .onTapGesture {
                    navigateTo(ContactPath(key: event.pubkey))
                }
            }
            if (!singleLine) {
                HStack {
                    if showUsername {
                        Text("@\(event.contact?.username ?? "...") · ")
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Text(event.ago)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        
        
        //        })
    }
}

struct NoteHeader_Previews: PreviewProvider {
    static var previews: some View {
        
//        let id = "1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0"
        VStack(alignment: .leading, spacing: 10) {
            
            if let event = PreviewFetcher.fetchEvent() {
                NoteHeader(event: event, singleLine: true)
            }
            
            if let event = PreviewFetcher.fetchEvent() {
                NoteHeader(event: event, singleLine: true)
            }
            
            if let event = PreviewFetcher.fetchEvent() {
                NoteHeader(event: event, singleLine: true)
            }
            
            Divider()
            
            if let event = PreviewFetcher.fetchEvent() {
                NoteHeader(event: event, singleLine: false)
            }
            
            if let event = PreviewFetcher.fetchEvent() {
                NoteHeader(event: event, singleLine: false)
            }
            
            if let event = PreviewFetcher.fetchEvent() {
                NoteHeader(event: event, singleLine: false)
            }
        }
        .padding()
        .withPreviewEnvironment()
    }
}
