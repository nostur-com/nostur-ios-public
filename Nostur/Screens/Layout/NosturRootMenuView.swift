//
//  NosturRootMenu.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI
import NavigationBackport

let NOSTUR_SIDEBAR_WIDTH = 310.0

struct NosturRootMenu: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var loggedInAccount: LoggedInAccount
    @State private var sm: SideBarModel = .shared
    @State private var askLoginInfo: AskLoginInfo? = nil
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        NosturMainView()
            .onReceive(NRState.shared.agoTimer) { _ in
                NewPostNotifier.shared.runCheck()
            }
            .environmentObject(loggedInAccount)
            .environmentObject(sm)
            .onOpenURL { url in
                self.handleUrl(url)
            }
            .sheet(item: $askLoginInfo, content: { askLoginInfo in
                NBNavigationStack {
                    AskLoginSheet(askLoginInfo: askLoginInfo, account: loggedInAccount.account)
                        .environmentObject(NRState.shared)
                        .environmentObject(themes)
                }
                .nbUseNavigationStack(.never)
                .presentationBackgroundCompat(themes.theme.background)
                .presentationDetents250medium()
            })
            .overlay {
                SideBarOverlay()
            }
            .overlay(alignment: .topLeading) {
                SideBar(account: loggedInAccount.account)
                    .frame(width: NOSTUR_SIDEBAR_WIDTH)
                    .edgesIgnoringSafeArea(.all)
            }
        #if DEBUG
            .overlay(alignment: .topTrailing) {
                if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                    Button("Test Toggle") {
                        sm.showSidebar.toggle()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        #endif
    }
    
    private func handleUrl(_ url:URL) {
        L.og.info("handleUrl: \(url.absoluteString)")
        
        let nostrlogin = url.absoluteString.matchingStrings(regex: "^nostr\\+login:(.*):([a-zA-Z0-9\\-_\\.]+)$")
        if nostrlogin.count == 1 && nostrlogin[0].count >= 3 {
            
            // can login even?
            if self.loggedInAccount.account.isFullAccount || (NRState.shared.fullAccountPubkeys.count > 0) {
                
                let domainString = nostrlogin[0][1]
                let challenge = nostrlogin[0][2]
                if let domain = URL(string: "https://" + domainString), let host = domain.host {
                    L.og.debug("Login to: \(host)?")
                    self.askLoginInfo = AskLoginInfo(domain: host, challenge: challenge)
                    return
                }
            }
            else {
                let domainString = nostrlogin[0][1]
                if let domain = URL(string: "https://" + domainString), let host = domain.host {
                    sendNotification(.anyStatus, ("Login requested on \(host) but no keys.", "APP_NOTICE"))
                }
            }
            return
        }
        
        if let regex = try? NSRegularExpression(pattern: "^nostr+login:(.*):([a-zA-Z0-9\\-_\\.]+)$", options: .caseInsensitive) {
            let nsRange = NSRange(url.absoluteString.startIndex..<url.absoluteString.endIndex, in: url.absoluteString)
            if regex.firstMatch(in: url.absoluteString, options: [], range: nsRange) != nil {
                L.og.info("Handle nostr login")
                return
            }
        }
        
        // CALLBACK FROM NWC
        if #available(iOS 16.0, *) {
            if let _ = url.absoluteString.firstMatch(of: /^nostur:\/\/nwc_callback(.*)/) {
                sendNotification(.nwcCallbackReceived, AlbyCallback(url:url))
                return
            }
        } else {
            if let regex = try? NSRegularExpression(pattern: "^nostur://nwc_callback(.*)", options: .caseInsensitive) {
                let nsRange = NSRange(url.absoluteString.startIndex..<url.absoluteString.endIndex, in: url.absoluteString)
                if regex.firstMatch(in: url.absoluteString, options: [], range: nsRange) != nil {
                    sendNotification(.nwcCallbackReceived, AlbyCallback(url: url))
                    return
                }
            }
        }
        
        // LINKS FROM ANYWHERE (NPUB1/NOTE1)
        let nostr = url.absoluteString.matchingStrings(regex: "^(nostur:|nostr:|nostur:nostr:)(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})$")
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
        
        // NADDR ARTICLE
        let nostrAddr = url.absoluteString.matchingStrings(regex: "^(nostur:|nostr:|nostur:nostr:)(naddr1)([023456789acdefghjklmnpqrstuvwxyz]+\\b)$")
        if nostrAddr.count == 1 && nostrAddr[0].count == 4 {
            L.og.info("nostr: naddr: \(nostrAddr[0][2])\(nostrAddr[0][3])")
            navigateTo(Naddr1Path(naddr1: "\(nostrAddr[0][2])\(nostrAddr[0][3])"))
            return
        }
        
        // (NEW) LINKS FROM ANYWHERE (NEVENT1/NPROFILE1)
        let nostrSharable = url.absoluteString.matchingStrings(regex: "^(nostur:|nostr:|nostur:nostr:)(nevent1|nprofile1)([023456789acdefghjklmnpqrstuvwxyz]+\\b)$")
        if nostrSharable.count == 1 && nostrSharable[0].count == 4 {
            L.og.info("nostr: nevent1/nprofile1: \(nostrSharable[0][2])\(nostrSharable[0][3])")
            UserDefaults.standard.setValue("Search", forKey: "selected_tab")
            if nostrSharable[0][2] == "nevent1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // TODO: Make proper loading into Search tab, instead of hoping the tab has loaded in time for .onReceive(receiveNotification(.navigateTo))
                    navigateTo(Nevent1Path(nevent1: "\(nostrSharable[0][2])\(nostrSharable[0][3])"))
                }
                return
            }
            if nostrSharable[0][2] == "nprofile1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // TODO: Make proper loading into Search tab, instead of hoping the tab has loaded in time for .onReceive(receiveNotification(.navigateTo))
                    navigateTo(Nprofile1Path(nprofile1: "\(nostrSharable[0][2])\(nostrSharable[0][3])"))
                }
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
            UserDefaults.standard.setValue("Search", forKey: "selected_tab")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                navigateTo(HashtagPath(hashTag: nosturHashtag[0][2]))
            }
            return
        }
        
        // SHARE NEW HIGHLIGHT
        if #available(iOS 16.0, *) {
            if let newHighlight = url.absoluteString.firstMatch(of: /^(nostur:highlight:)(.*)(:url:)(.*)(:title:)(.*)$/) {
                L.og.info("nostur: highlight")
                guard let url = newHighlight.output.4.removingPercentEncoding else { return }
                guard let selectedText = newHighlight.output.2.removingPercentEncoding else { return }
                let title = newHighlight.output.6.removingPercentEncoding
                sendNotification(.newHighlight, NewHighlight(url: url, selectedText: selectedText, title: title))
                return
            }
        } else {
            // Fallback on earlier versions
            let pattern = "^(nostur:highlight:)(.*)(:url:)(.*)(:title:)(.*)$"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: url.absoluteString, options: [], range: NSRange(url.absoluteString.startIndex..<url.absoluteString.endIndex, in: url.absoluteString)) {

                L.og.info("nostur: highlight")

                let ranges = (1..<regex.numberOfCaptureGroups + 1).map { match.range(at: $0) }
                guard ranges.count == 6 else { return }

                let substrings = ranges.map { Range($0, in: url.absoluteString).map { url.absoluteString[$0] } }
                guard let url = substrings[3]?.removingPercentEncoding,
                      let selectedText = substrings[1]?.removingPercentEncoding else { return }

                let title = substrings[5]?.removingPercentEncoding

                sendNotification(.newHighlight, NewHighlight(url: url, selectedText: selectedText, title: title))
                return
            }

        }
    }
}

struct NosturMainView: View {
    @ObservedObject private var ss: SettingsStore = .shared
    var body: some View {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            Color.random
        }
        else {
            if IS_CATALYST && ss.proMode {
                if #available(iOS 16.0, *) {
                    MacListsView()
                } else {
                    // Fallback on earlier versions
                    Text("Not yet")
                }
            }
            else {
                NosturTabsView()
            }
        }
    }
}

#Preview("Side bar menu") {
    PreviewContainer {
        VStack {
            if let loggedInAccount = NRState.shared.loggedInAccount {
                NosturRootMenu()
                    .environmentObject(loggedInAccount)
            }
        }
        .onAppear {
            Themes.default.loadRed()
        }
    }
}
