//
//  NoteHeader.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/02/2023.
//

import SwiftUI

struct NoteHeader: View {
    @EnvironmentObject var nav:NavigationModel
    @ObservedObject var event:Event
    var singleLine:Bool = true
    var hideEmojis:Bool
    
    init(event:Event, singleLine:Bool = true) {
        self.event = event
        self.singleLine = singleLine
        self.hideEmojis = SettingsStore.shared.hideEmojisInNames
    }
    
    var body: some View {
        //        NavigationLink(value: event, label: {
        
        VStack(alignment: .leading, spacing:0) { // Name + menu "replying to"
            HStack(spacing:2) {
                Group {
                    if (event.contact != nil) {
                        Text(event.contact!.authorName) // Name
                            .foregroundColor(.primary)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .layoutPriority(2)
                    }
                    else {
                        Text("Anon") // Name
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
                            Text("@\(event.contact?.username ?? "")").layoutPriority(1)
                            Text(" · ") //
                            Ago(event.date).layoutPriority(1) //
                        }
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    }
                }
                .onTapGesture {
                    nav.navigateTo(ContactPath(key: event.pubkey))
                }
//                Spacer()
//                Text(Date(timeIntervalSince1970: TimeInterval(event.created_at)), format: Date.VerbatimFormatStyle(format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)", timeZone: .current, calendar: .current))
//                    .padding(.trailing, 5)
//                    .lineLimit(1)
//                    .layoutPriority(1)
            }
            if (!singleLine) {
                Text("@\(event.contact?.username ?? event.authorKey) · \(event.ago)") //
//                        .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        
        
        //        })
    }
}

struct NoteHeader_Previews: PreviewProvider {
    static var previews: some View {
        let event7 = PreviewFetcher.fetchEvent("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
        if (event7 != nil) {
            NoteHeader(event: event7!)
                .withPreviewEnvironment()
        }
    }
}
