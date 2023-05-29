//
//  ContentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import CoreData
import Nuke
import AVFoundation

struct NosturTabsView: View {
    @StateObject private var dim = DIMENSIONS()
    @AppStorage("selected_tab") var selectedTab = "Main"
    @State var unread = 0
    @State var unreadDMs = 0
    
    var body: some View {
        let _ = Self._printChanges()
        HStack {
            VStack {
                Color.clear.frame(height: 0)
                    .modifier(SizeModifier())
                    .onPreferenceChange(SizePreferenceKey.self) { size in
                        guard size.width > 0 else { return }
                        dim.listWidth = size.width
                    }
                TabView(selection: $selectedTab) {
                    MainView()
                        .tabItem { Image(systemName: "house") }
                        .tag("Main")
                    
                    NotificationsContainer()
                        .tabItem { Image(systemName: "bell.fill") }
                        .tag("Notifications")
                        .badge(unread)
                    
                    Search()
                        .tabItem { Image(systemName: "magnifyingglass") }
                        .tag("Search")
                    
                    
                    BookmarksAndPrivateNotes()
                        .tabItem { Image(systemName: "bookmark") }
                        .tag("Bookmarks")
                    
                    DirectMessagesContainer()
                        .tabItem { Image(systemName: "envelope.fill") }
                        .tag("Messages")
                        .badge(unreadDMs)
                }
                .withSheets()
            }
            .frame(maxWidth: 600)
            .environmentObject(dim)
            .edgesIgnoringSafeArea(.all)
            if UIDevice.current.userInterfaceIdiom == .pad {
                TabbedDetailContainer()
            }
        }
        .onOpenURL { url in
            self.handleUrl(url)
        }
        .onReceive(receiveNotification(.updateNotificationsCount)) { notification in
            unread = (notification.object as! Int)
        }
        .onReceive(receiveNotification(.updateDMsCount)) { notification in
            unreadDMs = (notification.object as! Int)
        }
        .onAppear {
            ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
            configureAudioSession()
        }
    }
    
    func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
}

extension NosturTabsView {
    func handleUrl(_ url:URL) {
        L.og.info("handleUrl: \(url.absoluteString)")
        // LINKS FROM ANYWHERE (NPUB1/NOTE1)
        let nostr = url.absoluteString.matchingStrings(regex: "^(nostr:)(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})$")
        if nostr.count == 1 && nostr[0].count == 4 {
            L.og.info("nostr: link: \(nostr[0][2])\(nostr[0][3])")
            let key = try! NIP19(displayString: "\(nostr[0][2])\(nostr[0][3])")
            L.og.info("nostr: link::  \(key.hexString)")
            if nostr[0][2] == "npub1" {
                navigateTo(ContactPath(key: key.hexString))
                return
            }
            if nostr[0][2] == "note1" {
                navigateTo(NotePath(id: key.hexString))
                return
            }
        }
        
        // (NEW) LINKS FROM ANYWHERE (NEVENT1/NPROFILE1)
        let nostrSharable = url.absoluteString.matchingStrings(regex: "^(nostr:)(nevent1|nprofile1)([023456789acdefghjklmnpqrstuvwxyz]+\\b)$")
        if nostrSharable.count == 1 && nostrSharable[0].count == 4 {
            L.og.info("nostr: nevent1/nprofile1: \(nostrSharable[0][2])\(nostrSharable[0][3])")
            selectedTab = "Search"
            if nostrSharable[0][2] == "nevent1" {
                navigateTo(Nevent1Path(nevent1: "\(nostrSharable[0][2])\(nostrSharable[0][3])"))
                return
            }
            if nostrSharable[0][2] == "nprofile1" {
                navigateTo(Nprofile1Path(nprofile1: "\(nostrSharable[0][2])\(nostrSharable[0][3])"))
                return
            }
        }

        // LINKS FROM WITHIN NOSTUR
        let nostur = url.absoluteString.matchingStrings(regex: "^(nostur:)(p:|e:)([0-9a-z]{64})$")
        if nostur.count == 1 && nostur[0].count == 4 {
            L.og.info("nostur: link: \(nostur[0][2])\(nostur[0][3])")
            if nostur[0][2] == "p:" {
                navigateTo(ContactPath(key: nostur[0][3]))
                return
            }
            if nostur[0][2] == "e:" {
                navigateTo(NotePath(id: nostur[0][3]))
                return
            }
        }

        // LINKS FROM ANYWHERE (HEX)
        let nostrHex = url.absoluteString.matchingStrings(regex: "^(nostr:)(p:|e:)([0-9a-z]{64})$")
        if nostrHex.count == 1 && nostrHex[0].count == 4 {
            L.og.info("nostur: link: \(nostrHex[0][2])\(nostrHex[0][3])")
            if nostrHex[0][2] == "p:" {
                navigateTo(ContactPath(key: nostrHex[0][3]))
                return
            }
            if nostrHex[0][2] == "e:" {
                navigateTo(NotePath(id: nostrHex[0][3]))
                return
            }
        }

        // HASHTAG LINKS FROM WITHIN NOSTUR
        let nosturHashtag = url.absoluteString.matchingStrings(regex: "^(nostur:t:)(\\S+)$")
        if nosturHashtag.count == 1 && nosturHashtag[0].count == 3 {
            L.og.info("nostur: hashtag: \(nosturHashtag[0][2])")
            selectedTab = "Search"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                navigateTo(HashtagPath(hashTag: nosturHashtag[0][2]))
            }
            return
        }
        
        // SHARE NEW HIGHLIGHT
        if let newHighlight = url.absoluteString.firstMatch(of: /^(nostur:highlight:)(.*)(:url:)(.*)(:title:)(.*)$/) {
            L.og.info("nostur: highlight")
            guard let url = newHighlight.output.4.removingPercentEncoding else { return }
            guard let selectedText = newHighlight.output.2.removingPercentEncoding else { return }
            let title = newHighlight.output.6.removingPercentEncoding
            sendNotification(.newHighlight, NewHighlight(url: url, selectedText: selectedText, title: title))
            return
        }
    }
}
