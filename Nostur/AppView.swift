//
//  AppView.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/05/2023.
//

import SwiftUI
import Nuke
import NostrEssentials

struct AppView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var accountsState: AccountsState
    @EnvironmentObject private var themes: Themes
    @State private var viewState: ViewState = .starting

    var body: some View {
        ZStack {
            switch viewState {
            case .starting:
                themes.theme.listBackground
            case .onboarding:
                Onboarding()
            case .loggedIn(let loggedInAccount):
                NosturMainView()
                    .environment(\.theme, themes.theme)
                    .tint(themes.theme.accent)
                    .accentColor(themes.theme.accent)
                    .environmentObject(loggedInAccount)
                    .onAppear {
                        ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
                    }
                    .onChange(of: scenePhase) { newScenePhase in
                        handleNewScenePhase(newScenePhase)
                    }
                    .onOpenURL { url in
                        handleUrl(url, loggedInAccount: loggedInAccount)
                    }
                    .onReceive(AppState.shared.minuteTimer) { _ in
                        NewPostNotifier.shared.runCheck()
                    }
                    .overlay {
                        if #available(iOS 16.0, *) {
                            AppReviewView()
                        }
                    }
            case .databaseError:
                DatabaseProblemView()
            }
        }
        .onChange(of: accountsState.loggedInAccount) { newLoggedInAccount in
            // Don't set to .loggedIn too soon, need to wait for startNosturing() to have finished or .connections will be empty (needed in MainFeedsScreen)
            guard AppState.shared.finishedTasks.contains(.didRunConnectAll) else { return }

            viewState = if let newLoggedInAccount {
                .loggedIn(newLoggedInAccount)
            } else {
                .onboarding
            }
        }
        .task {
            if DataProvider.shared().databaseProblem {
                viewState = .databaseError; return
            }

            await startNosturing() // Need stuff to be ready before NosturMainView() appears
            
            // viewState = .loggedIn makes NosturMainView() appear
            viewState = if let loggedInAccount = accountsState.loggedInAccount {
                .loggedIn(loggedInAccount)
            } else {
                .onboarding
            }
        }
    }
}

extension AppView {
    
    enum ViewState: Equatable {
        case starting
        case onboarding
        case loggedIn(LoggedInAccount)
        case databaseError
    }
    
    private func loadAccount() {
        if let loggedInAccount = AccountsState.shared.loggedInAccount {
            viewState = .loggedIn(loggedInAccount)
        }
        else {
            viewState = .onboarding
        }
    }
    
    private func handleNewScenePhase(_ newScenePhase: ScenePhase) {
        switch newScenePhase {
        case .active:
            // Prevent auto-lock while playing
            UIApplication.shared.isIdleTimerDisabled = AnyPlayerModel.shared.isPlaying
            NewPostNotifier.shared.reload()
            
            AppState.shared.agoShouldUpdateSubject.send() // Update ago timestamps
            
            if !IS_CATALYST {
                if (AppState.shared.appIsInBackground) { // if we were actually in background (from .background, not just a few seconds .inactive)
                    AppState.shared.appIsInBackground = false // needs to set before we call other actions
                    ConnectionPool.shared.connectAll()
                    sendNotification(.scenePhaseActive)
                    FeedsCoordinator.shared.resumeFeeds()
                    NotificationsViewModel.shared.restoreSubscriptions()
                    AppState.shared.startTaskTimers()
                }
            }
            else {
                AppState.shared.appIsInBackground = false
                ConnectionPool.shared.connectAll()
                sendNotification(.scenePhaseActive)
                FeedsCoordinator.shared.resumeFeeds()
                NotificationsViewModel.shared.restoreSubscriptions()
                AppState.shared.startTaskTimers()
            }
            
            
        case .background:
            AppState.shared.appIsInBackground = true
            FeedsCoordinator.shared.saveFeedStates()
            if !IS_CATALYST {
                FeedsCoordinator.shared.pauseFeeds()
                scheduleDatabaseCleaningIfNeeded()
            }
            if SettingsStore.shared.receiveLocalNotifications {
                guard let account = account() else { return }
                if account.lastSeenPostCreatedAt == 0 {
                    account.lastSeenPostCreatedAt = Int64(Date.now.timeIntervalSince1970)
                }
                UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: "last_dm_local_notification_timestamp")
                UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: "last_local_notification_timestamp")
                UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: "last_new_posts_local_notification_timestamp")
                scheduleAppRefresh()
            }
            
            sendNotification(.scenePhaseBackground)
            
            let lastMaintenanceTimestamp = Date(timeIntervalSince1970: TimeInterval(SettingsStore.shared.lastMaintenanceTimestamp))
            let hoursAgo = Date(timeIntervalSinceNow: -432_000)
            let runNow = lastMaintenanceTimestamp < hoursAgo
            
            if IS_CATALYST || runNow { // macOS doesn't do background processing tasks, so we do it here instead of .scheduleDatabaseCleaningIfNeeded(). OR we do it if for whatever reason iOS has not run it for 5 days in background the processing task
                // 1. Clean up
                Task {
                    let didRun = await Maintenance.dailyMaintenance(context: bg())
                    if didRun {
                        await Importer.shared.preloadExistingIdsCache()
                    }
                    else {
                        DataProvider.shared().saveToDiskNow(.viewContext) // need to save to sync cloud for feed.lastRead
                    }
                }
            }
            else {
                DataProvider.shared().saveToDiskNow(.viewContext) // need to save to sync cloud for feed.lastRead
            }
        case .inactive:
            break
            
        default:
            break
        }
    }
    
    private func handleUrl(_ url: URL, loggedInAccount: LoggedInAccount) {
#if DEBUG
    L.og.debug("handleUrl: \(url.absoluteString)")
#endif
        
    // HANDLE ADD RELAY FEED
    let nosturRelay = url.absoluteString.matchingStrings(regex: "^(nostur:add_relay:)(\\S+)$")
    if nosturRelay.count == 1 && nosturRelay[0].count == 3 {
#if DEBUG
        L.og.info("nostur: add_relay: \(nosturRelay[0][2])")
#endif  
        AppSheetsModel.shared.relayFeedPreviewSheetInfo = RelayFeedPreviewInfo(relayUrl: normalizeRelayUrl(nosturRelay[0][2]))
        return
    }
    
    let nostrlogin = url.absoluteString.matchingStrings(regex: "^nostr\\+login:(.*):([a-zA-Z0-9\\-_\\.]+)$")
    if nostrlogin.count == 1 && nostrlogin[0].count >= 3 {
        
        // can login even?
        if loggedInAccount.account.isFullAccount || (AccountsState.shared.bgFullAccountPubkeys.count > 0) {
            
            let domainString = nostrlogin[0][1]
            let challenge = nostrlogin[0][2]
            if let domain = URL(string: "https://" + domainString), let host = domain.host {
#if DEBUG
                L.og.debug("Login to: \(host)?")
#endif
                AppSheetsModel.shared.askLoginInfo = AskLoginInfo(domain: host, challenge: challenge)
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
#if DEBUG
            L.og.info("Handle nostr login")
#endif
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
#if DEBUG
        L.og.info("nostr: link: \(nostr[0][2])\(nostr[0][3])")
#endif
        let key = try! NIP19(displayString: "\(nostr[0][2])\(nostr[0][3])")
#if DEBUG
        L.og.info("nostr: link::  \(key.hexString)")
#endif
        if nostr[0][2] == "npub1" {
            navigateTo(ContactPath(key: key.hexString), context: "Default")
            return
        }
        if nostr[0][2] == "note1" {
            navigateTo(NotePath(id: key.hexString), context: "Default")
            return
        }
    }
    
    // NADDR ARTICLE
    let nostrAddr = url.absoluteString.matchingStrings(regex: "^(nostur:|nostr:|nostur:nostr:)(naddr1)([023456789acdefghjklmnpqrstuvwxyz]+\\b)$")
    if nostrAddr.count == 1 && nostrAddr[0].count == 4 {
#if DEBUG
        L.og.info("nostr: naddr: \(nostrAddr[0][2])\(nostrAddr[0][3])")
#endif
        navigateTo(Naddr1Path(naddr1: "\(nostrAddr[0][2])\(nostrAddr[0][3])"), context: "Default")
        return
    }
    
    // (NEW) LINKS FROM ANYWHERE (NEVENT1/NPROFILE1)
    let nostrSharable = url.absoluteString.matchingStrings(regex: "^(nostur:|nostr:|nostur:nostr:)(nevent1|nprofile1)([023456789acdefghjklmnpqrstuvwxyz]+\\b)$")
    if nostrSharable.count == 1 && nostrSharable[0].count == 4 {
#if DEBUG
        L.og.info("nostr: nevent1/nprofile1: \(nostrSharable[0][2])\(nostrSharable[0][3])")
#endif
        UserDefaults.standard.setValue("Search", forKey: "selected_tab")
        if nostrSharable[0][2] == "nevent1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // TODO: Make proper loading into Search tab, instead of hoping the tab has loaded in time for .onReceive(receiveNotification(.navigateTo))
                navigateTo(Nevent1Path(nevent1: "\(nostrSharable[0][2])\(nostrSharable[0][3])"), context: "Default")
            }
            return
        }
        if nostrSharable[0][2] == "nprofile1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // TODO: Make proper loading into Search tab, instead of hoping the tab has loaded in time for .onReceive(receiveNotification(.navigateTo))
                navigateTo(Nprofile1Path(nprofile1: "\(nostrSharable[0][2])\(nostrSharable[0][3])"), context: "Default")
            }
            return
        }
    }
    
    // LINKS FROM WITHIN NOSTUR
    let nostur = url.absoluteString.matchingStrings(regex: "^(nostur:)(p:|e:)([0-9a-z]{64})$")
    if nostur.count == 1 && nostur[0].count == 4 {
#if DEBUG
        L.og.info("nostur: link: \(nostur[0][2])\(nostur[0][3])")
#endif
        if nostur[0][2] == "p:" {
            navigateTo(ContactPath(key: nostur[0][3]), context: "Default")
            return
        }
        if nostur[0][2] == "e:" {
            navigateTo(NotePath(id: nostur[0][3]), context: "Default")
            return
        }
    }
    
    // LINKS FROM ANYWHERE (HEX)
    let nostrHex = url.absoluteString.matchingStrings(regex: "^(nostr:)(p:|e:)([0-9a-z]{64})$")
    if nostrHex.count == 1 && nostrHex[0].count == 4 {
#if DEBUG
        L.og.info("nostur: link: \(nostrHex[0][2])\(nostrHex[0][3])")
#endif
        if nostrHex[0][2] == "p:" {
            navigateTo(ContactPath(key: nostrHex[0][3]), context: "Default")
            return
        }
        if nostrHex[0][2] == "e:" {
            navigateTo(NotePath(id: nostrHex[0][3]), context: "Default")
            return
        }
    }
    
    // HASHTAG LINKS FROM WITHIN NOSTUR
    let nosturHashtag = url.absoluteString.matchingStrings(regex: "^(nostur:t:)(\\S+)$")
    if nosturHashtag.count == 1 && nosturHashtag[0].count == 3 {
#if DEBUG
        L.og.info("nostur: hashtag: \(nosturHashtag[0][2])")
#endif
        UserDefaults.standard.setValue("Search", forKey: "selected_tab")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            navigateTo(HashtagPath(hashTag: nosturHashtag[0][2]), context: "Default")
        }
        return
    }
    
    // SHARE NEW HIGHLIGHT
    if #available(iOS 16.0, *) {
        if let newHighlight = url.absoluteString.firstMatch(of: /^(nostur:highlight:)(.*)(:url:)(.*)(:title:)(.*)$/) {
#if DEBUG
            L.og.info("nostur: highlight")
#endif
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
#if DEBUG
            L.og.info("nostur: highlight")
#endif
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

#Preview("NosturMainView.loggedIn") {
    PreviewContainer {
        NosturMainView()
    }
}
