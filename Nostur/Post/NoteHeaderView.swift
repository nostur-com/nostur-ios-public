//
//  NoteHeaderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2023.
//
import SwiftUI

struct NoteHeaderView: View {
     
    let vPost:VPost
    @ObservedObject var event:Event
    var singleLine:Bool = true
    
    init(vPost: VPost, singleLine: Bool = true) {
        self.vPost = vPost
        self.event = vPost.event
        self.singleLine = singleLine
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing:0) { // Name + menu "replying to"
            if let contact = event.contact_ {
                HStack(spacing:2) {
                    Group {
                        Text(contact.authorName) // Name
                            .foregroundColor(.primary)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .layoutPriority(2)
                        
                        if (contact.nip05veried) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(Color("AccentColor"))
                                .layoutPriority(3)
                        }
                        
                        if (singleLine) {
                            Group {
                                Text("@\(contact.username)").layoutPriority(1)
                                Text(" · ") //
                                Ago(vPost.date)
                                    .layoutPriority(2)
                            }
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        }
                    }
                }
                if (!singleLine) {
                    HStack {
                        Text("@\(contact.username)").layoutPriority(1)
                        Text(" · ") //
                        Ago(vPost.date)
                            .layoutPriority(2)
                    }
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }
            }
            else {
                HStack(spacing:2) {
                    Group {
                        
                        Text(vPost.displayName) // Name
                            .foregroundColor(.primary)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .layoutPriority(2)
                        
                        if (vPost.nip05verified) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(Color("AccentColor"))
                                .layoutPriority(3)
                        }
                        
                        if (singleLine) {
                            Group {
                                Text("@\(vPost.username)").layoutPriority(1)
                                Text(" · ") //
                                Ago(vPost.date)
                                    .layoutPriority(2)
                            }
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        }
                    }
                }
                if (!singleLine) {
                    Text("@\(vPost.username) · 1s")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct PreviewHeaderView: View {

    var authorName:String
    var username:String
    var nip05verified = false
    var singleLine:Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing:0) { // Name + menu "replying to"
            HStack(spacing:2) {
                Group {
    
                    Text(authorName) // Name
                        .foregroundColor(.primary)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .layoutPriority(2)

                    if (nip05verified) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(Color("AccentColor"))
                            .layoutPriority(3)
                    }
                    
                    
                    
                    if (singleLine) {
                        Group {
                            Text("@\(username)").layoutPriority(1)
                            Text(" · ") //
                            Text("1s")
                                .layoutPriority(2)
                        }
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    }
                }
            }
            if (!singleLine) {
                Text("@\(username) · 1s")
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct NameAndNip: View {
    @ObservedObject var contact:Contact // for rendering nip check (after just verified) etc

    var body: some View {
        Text(contact.authorName) // Name
            .foregroundColor(.primary)
            .fontWeight(.bold)
            .lineLimit(1)
            .layoutPriority(2)

        if (contact.nip05veried) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(Color("AccentColor"))
                .layoutPriority(3)
        }
    }
}

struct NoteHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        
        VStack {
            PreviewHeaderView(authorName: "Fabian", username: "fabian")
            
            let event7 = PreviewFetcher.fetchVPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
            if (event7 != nil) {
                NoteHeaderView(vPost: event7!)
                    .withPreviewEnvironment()
            }
        }
        
    }
}
