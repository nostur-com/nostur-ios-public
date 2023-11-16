//
//  NoteHeaderViewEvent.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/05/2023.
//

import SwiftUI

struct NoteHeaderViewEvent: View {
    
    @ObservedObject var event:Event
    var singleLine:Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing:0) { // Name + menu "replying to"
            if let contact = event.contact {
                PostHeaderEvent(contact: contact, event:event, singleLine:singleLine)
                    .frame(maxWidth: .infinity, alignment:.leading)
            }
            else {
                PlaceholderPostHeaderEvent(event: event, singleLine: singleLine)
                    .frame(maxWidth: .infinity, alignment:.leading)
                    .onAppear {
                        EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "NoteHeaderViewEvent.001")
                        QueuedFetcher.shared.enqueue(pTag: event.pubkey)
                    }
                    .onDisappear {
                        QueuedFetcher.shared.dequeue(pTag: event.pubkey)
                    }
            }
        }
    }
}

struct PlaceholderPostHeaderEvent: View {
    @ObservedObject private var settings:SettingsStore = .shared
    let event:Event
    let singleLine:Bool
    
    var body: some View {
        HStack(spacing:2) {
            Group {
                Text(String(event.pubkey.suffix(11))) // Name
                    .foregroundColor(.primary)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .layoutPriority(2)
                
                if (singleLine) {
                    Ago(event.date)
                        .equatable()
                        .font(.subheadline)
                        .layoutPriority(2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if settings.postUserAgentEnabled {
                        Text(String(format: "via %@", "Nostur"))
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                            .layoutPriority(3)
                    }
                }
            }
        }
        if (!singleLine) {
            HStack {
                Ago(event.date)
                    .equatable()
                    .layoutPriority(2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if settings.postUserAgentEnabled {
                    Text(String(format: "via %@", "Nostur"))
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                        .layoutPriority(3)
                }
            }
        }
    }
}

struct PostHeaderEvent: View {
    @ObservedObject private var settings:SettingsStore = .shared
    @EnvironmentObject private var themes:Themes
    @ObservedObject var contact:Contact
    let event:Event
    let singleLine:Bool
    
    var body: some View {
        HStack(spacing:5) {
            Group {
                Text(contact.anyName) // Name
                    .foregroundColor(.primary)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .layoutPriority(2)
                
                if contact.nip05veried, let nip05 = contact.nip05 {
                    NostrAddress(nip05: nip05, shortened: contact.anyName.lowercased() == contact.nip05nameOnly.lowercased())
                        .layoutPriority(3)
                }
                
                if (singleLine) {
                    Ago(event.date)
                        .equatable()
                        .layoutPriority(2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if settings.displayUserAgentEnabled, let via = event.via {
                        Text(String(format: "via %@", via))
                            .font(.subheadline)
                            .lineLimit(1)
                            .layoutPriority(3)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            if contact.metadata_created_at == 0 {
                EventRelationsQueue.shared.addAwaitingContact(contact, debugInfo: "NoteHeaderViewEvent.001")
                QueuedFetcher.shared.enqueue(pTag: contact.pubkey)
            }
        }
        .onDisappear {
            if contact.metadata_created_at == 0 {
                QueuedFetcher.shared.dequeue(pTag: contact.pubkey)
            }
        }
        if (!singleLine) {
            HStack {
                Ago(event.date)
                    .equatable()
                    .layoutPriority(2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if settings.displayUserAgentEnabled, let via = event.via {
                    Text(String(format: "via %@", via))
                        .font(.subheadline)
                        .lineLimit(1)
                        .layoutPriority(3)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct NameAndNipContact: View {
    @EnvironmentObject private var themes:Themes
    @ObservedObject var contact:Contact // for rendering nip check (after just verified) etc
    
    var body: some View {
        Text(contact.anyName) // Name
            .foregroundColor(.primary)
            .fontWeight(.bold)
            .lineLimit(1)
            .layoutPriority(2)
        
        if contact.nip05veried, let nip05 = contact.nip05 {
            NostrAddress(nip05: nip05, shortened: contact.anyName.lowercased() == contact.nip05nameOnly.lowercased())
                .layoutPriority(3)
        }
    }
}

struct NoteHeaderViewEvent_Previews: PreviewProvider {
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            VStack(spacing: 10) {
                if let event = PreviewFetcher.fetchEvent("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0") {
                    NoteHeaderViewEvent(event: event, singleLine: false)
                }
                
                if let event = PreviewFetcher.fetchEvent() {
                    NoteHeaderViewEvent(event: event, singleLine: false)
                }
                
                if let event = PreviewFetcher.fetchEvent() {
                    NoteHeaderViewEvent(event: event, singleLine: false)
                }
                
                Divider()
                
                if let event = PreviewFetcher.fetchEvent() {
                    NoteHeaderViewEvent(event: event, singleLine: true)
                }
                
                if let event = PreviewFetcher.fetchEvent() {
                    NoteHeaderViewEvent(event: event, singleLine: true)
                }
                
                if let event = PreviewFetcher.fetchEvent() {
                    NoteHeaderViewEvent(event: event, singleLine: true)
                }
            }
            .padding()
        }
    }
}
