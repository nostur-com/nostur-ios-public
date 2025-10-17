//
//  AppView.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/05/2023.
//

import SwiftUI
import Nuke

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
                    .onReceive(AppState.shared.minuteTimer) { _ in
                        NewPostNotifier.shared.runCheck()
                    }
                    .overlay {
                        if #available(iOS 16.0, *) {
                            AppReviewView()
                        }
                    }
                    .onOpenURL(perform: handleUrl)
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
                    NotificationsViewModel.restoreSubscriptions()
                    AppState.shared.startTaskTimers()
                }
            }
            else {
                AppState.shared.appIsInBackground = false
                ConnectionPool.shared.connectAll()
                sendNotification(.scenePhaseActive)
                FeedsCoordinator.shared.resumeFeeds()
                NotificationsViewModel.restoreSubscriptions()
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
}

#Preview("NosturMainView.loggedIn") {
    PreviewContainer {
        NosturMainView()
    }
}
