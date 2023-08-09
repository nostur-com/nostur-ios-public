////
////  NoteHeader.swift
////  Nostur
////
////  Created by Fabian Lachman on 23/02/2023.
////
//
//import SwiftUI
//
//struct NoteHeader: View {
//    
//    @ObservedObject var event:Event
//    var singleLine:Bool = true
//    var hideEmojis:Bool
//    
//    init(event:Event, singleLine:Bool = true) {
//        self.event = event
//        self.singleLine = singleLine
//        self.hideEmojis = SettingsStore.shared.hideEmojisInNames
//    }
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing:0) { // Name + menu "replying to"
//            HStack(spacing:5) {
//                Group {
//                    if (event.contact != nil) {
//                        Text(event.contact!.anyName) // Name
//                            .foregroundColor(.primary)
//                            .fontWeight(.bold)
//                            .lineLimit(1)
//                            .layoutPriority(2)
//                    }
//                    else {
//                        Text("...") // Name
//                            .foregroundColor(.primary)
//                            .fontWeight(.bold)
//                            .lineLimit(1)
//                            .redacted(reason: .placeholder)
//                    }
//                    
//                    if (event.contact?.nip05veried ?? false) {
//                        Image(systemName: "checkmark.seal.fill")
//                            .foregroundColor(Color("AccentColor"))
//                            .layoutPriority(3)
//                    }
//                    
//                    if (singleLine) {
//                        Ago(event.date)
//                            .equatable()
//                            .layoutPriority(1)
//                            .foregroundColor(.secondary)
//                            .lineLimit(1)
//                    }
//                }
//                .onTapGesture {
//                    navigateTo(ContactPath(key: event.pubkey))
//                }
//            }
//            if (!singleLine) {
//                Text(event.ago)
//                    .foregroundColor(.secondary)
//                    .lineLimit(1)
//            }
//        }
//    }
//}
//
//struct NoteHeader_Previews: PreviewProvider {
//    static var previews: some View {
//        PreviewContainer({ pe in
//            pe.loadContacts()
//            pe.loadPosts()
//        }) {
//            VStack(alignment: .leading, spacing: 10) {
//                
//                if let event = PreviewFetcher.fetchEvent() {
//                    NoteHeader(event: event, singleLine: true)
//                }
//                
//                if let event = PreviewFetcher.fetchEvent() {
//                    NoteHeader(event: event, singleLine: true)
//                }
//                
//                if let event = PreviewFetcher.fetchEvent() {
//                    NoteHeader(event: event, singleLine: true)
//                }
//                
//                Divider()
//                
//                if let event = PreviewFetcher.fetchEvent() {
//                    NoteHeader(event: event, singleLine: false)
//                }
//                
//                if let event = PreviewFetcher.fetchEvent() {
//                    NoteHeader(event: event, singleLine: false)
//                }
//                
//                if let event = PreviewFetcher.fetchEvent() {
//                    NoteHeader(event: event, singleLine: false)
//                }
//            }
//            .padding()
//        }
//    }
//}
