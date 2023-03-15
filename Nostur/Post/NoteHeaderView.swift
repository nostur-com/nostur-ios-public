//
//  NoteHeaderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2023.
//
import SwiftUI
import Compactor

struct NoteHeaderView: View {
    let nav:NavigationModel = .shared
    let vPost:VPost
    var singleLine:Bool = true
    var hideEmojis:Bool
    
    var ago: String {
        get {
            let f = TimeCompactor(ifZero: nil, style: .short, roundSmallToWhole: true)
            return f.string(from: Double(Date.now.timeIntervalSince(vPost.createdAt)) as NSNumber)!
        }
    }
    
    init(vPost:VPost, singleLine:Bool = true) {
        self.vPost = vPost
        self.singleLine = singleLine
        self.hideEmojis = SettingsStore.shared.hideEmojisInNames
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing:0) { // Name + menu "replying to"
            HStack(spacing:2) {
                Group {
                    if (vPost.vContact != nil) {
                        Text(vPost.vContact!.displayName) // Name
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
                    
                    if (vPost.vContact?.isNip05Verified ?? false) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.blue)
                            .layoutPriority(3)
                    }
                    
                    if (singleLine) {
                        Group {
                            Text("@\(vPost.vContact?.username ?? "")").layoutPriority(1)
                            Text(" · ") //
                            Text(ago).layoutPriority(1) //
                        }
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    }
                }
                .onTapGesture {
                    nav.navigateTo(ContactPath(key: vPost.pubkey))
                }
            }
            if (!singleLine) {
                Text("@\(vPost.vContact?.username ?? String(vPost.npub.prefix(11))) · \(ago)")
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct NoteHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        let event7 = PreviewFetcher.fetchVPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
        if (event7 != nil) {
            NoteHeaderView(vPost: event7!)
                .withPreviewEnvironment()
        }
    }
}
