//
//  BackgroundNotifications.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/12/2023.
//

import SwiftUI
import BackgroundTasks
import UserNotifications

// AppDelegate is needed to handle notification taps
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    // Keep the app portrait-only by default. Full-screen video temporarily changes
    // this to landscape and restores portrait when playback leaves full screen.
    static var supportedOrientations: UIInterfaceOrientationMask = .portrait
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.supportedOrientations
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Wire notification delegate
        UNUserNotificationCenter.current().delegate = self

        BGTaskScheduler.shared.register(forTaskWithIdentifier: WoTBackgroundRefresh.identifier, using: nil) { task in
            let work = Task { @MainActor in
                let success = await WoTBackgroundRefresh.run()
                WoTBackgroundRefresh.schedule()
                task.setTaskCompleted(success: success && !Task.isCancelled)
            }
            task.expirationHandler = { work.cancel() }
        }
        
        // Register background processing task here (SwiftUI doesn't support PROCESSING tasks yet, only REFRESH tasks)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.nostur.db-cleanup", using: nil) { task in
            // Downcast the parameter to a processing task as this identifier is used for a processing request.
            self.handleDatabaseCleaning(task: task as! BGProcessingTask)
        }
        
        // Register appRefresh task here instead of in SwiftUI, should fix crash according to: https://developer.apple.com/forums/thread/775497?answerId=827147022#827147022
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.nostur.app-refresh", using: nil) { task in
            // Downcast the parameter to a processing task as this identifier is used for a processing request.
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        
        return true
    }

    // Handle notification type, go to proper tab/subtab on tap
    func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
#if DEBUG
        L.og.debug("userNotificationCenter.didReceive")
#endif
        let userInfo = response.notification.request.content.userInfo
        
        if let tapDestination = userInfo["tapDestination"] as? String {
            switch tapDestination {
            case "Mentions":
                setSelectedTab("Notifications")
                setSelectedNotificationsTab("Mentions")
            case "New Posts":
                setSelectedTab("Notifications")
                setSelectedNotificationsTab("New Posts")
            case "Messages":
                goToDMs()
            default:
                break
            }
        }
        completionHandler()
    }
    
    // This method will be called when a notification is delivered while the app is in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show the notification as a banner, sound, etc.
        completionHandler([.banner, .sound])
    }
    
    // Delete feed entries older than one day.
    func handleDatabaseCleaning(task: BGProcessingTask) {
#if DEBUG
        L.maintenance.debug("handleDatabaseCleaning()")
#endif
        let context = DataProvider.shared().newTaskContext()
        let work = Task {
            let didRun = await Maintenance.dailyMaintenance(context: context, force: true)
            if didRun { await Importer.shared.preloadExistingIdsCache() }
            task.setTaskCompleted(success: didRun && !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
    
    func handleAppRefresh(task: BGAppRefreshTask) {
#if DEBUG
        L.og.debug(".appRefresh()")
#endif
        
        guard SettingsStore.shared.receiveLocalNotifications else {
#if DEBUG
            L.og.debug(".appRefresh() - receiveLocalNotifications: false - skipping")
#endif
            task.setTaskCompleted(success: true)
            return
        }
        // Always schedule the next refresh
        scheduleAppRefresh(seconds: 180.0)
        
        // Check for any new notifications (relays), if there are unread mentions or new posts (notification bell) it will trigger a (iOS) notification
        let completion = BackgroundRefreshCompletion { success in
            task.setTaskCompleted(success: success)
        }
        let work = Task { @MainActor in
            var success = false
            defer { completion.finish(success && !Task.isCancelled) }
            guard !Task.isCancelled else { return }
            // Prepare
            guard !AccountsState.shared.activeAccountPublicKey.isEmpty else {
                success = true
                return
            }
            if !Importer.shared.didPreload {
                await Importer.shared.preloadExistingIdsCache()
            }
            
            guard !Task.isCancelled else { return }
            guard let account = try? CloudAccount.fetchAccount(publicKey: AccountsState.shared.activeAccountPublicKey, context: viewContext())
            else {
                success = true
                return
            }
            let accountData = account.toStruct()
            if !WebOfTrust.shared.theWoTisReady {
                WebOfTrust.shared.loadWoT()
            }
            
            // Setup connections
            let relays: [RelayData] = CloudRelay.fetchAll(context: DataProvider.shared().viewContext).map { $0.toStruct() }
            for relay in relays {
                ConnectionPool.shared.addConnection(relay)
            }
            ConnectionPool.shared.connectAll()
            
            // Do checks
            await checkForNotifications(accountData: accountData)
            guard !Task.isCancelled else { return }
            await checkForDMNotifications(accountData: accountData)
            guard !Task.isCancelled else { return }
            
            // Check new posts
            NewPostNotifier.shared.runCheck(force: true)
            
            if UserDefaults.standard.bool(forKey: SettingsStore.Keys.enableLiveEvents) {
                LiveEventsModel.shared.fetchFromRelays()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                guard UIApplication.shared.applicationState == .background else { return }
                ConnectionPool.shared.disconnectAll()
            }
            
            success = true
        }
        task.expirationHandler = {
            work.cancel()
            completion.finish(false)
            Task { @MainActor in
                guard UIApplication.shared.applicationState == .background else { return }
                ConnectionPool.shared.disconnectAll()
            }
        }
    }
}

// Schedule a background fetch task
func scheduleAppRefresh(seconds: TimeInterval = 60.0) {
#if DEBUG
    L.og.debug("scheduleAppRefresh()")
#endif
    let request = BGAppRefreshTaskRequest(identifier: "com.nostur.app-refresh")
    request.earliestBeginDate = .now.addingTimeInterval(seconds) // 60 seconds. Should maybe be longer for battery life, 5-30 minutes? Need to test
    try? BGTaskScheduler.shared.submit(request)
}

// Request permissions to send local notifications
func requestNotificationPermission(redirectToSettings:Bool = false) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
        if !success {
#if DEBUG
            L.og.error("\(error?.localizedDescription ?? "Error with UNUserNotificationCenter.current().requestAuthorization")")
#endif
            DispatchQueue.main.async {
                SettingsStore.shared.receiveLocalNotifications = false
                if redirectToSettings {
                    if let appSettings = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(appSettings) {
                        UIApplication.shared.open(appSettings)
                    }
                }
            }
        }
    }
}

// Schedule a local notification for 1 or more mentions
func scheduleMentionNotification(_ mentions: [Mention], pubkey: String) {
#if DEBUG
    L.og.debug("scheduleMentionNotification()")
#endif
    
    // Remember timestamp so we only show newer notifications next time
    UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: accountSpecificKey(pubkey, forKey: "last_local_notification_timestamp"))
    
    // Create the notificatgion
    let content = UNMutableNotificationContent()
    let title = Set(mentions.map { $0.name }).formatted(.list(type: .and)) // "John and Jim"
    let roomTitles = Set(mentions.compactMap(\.roomTitle)).formatted(.list(type: .and))
    content.title = if title.isEmpty { "New reply" } else { title } // if title == "" then iOS will show the App title instead, which makes it look like there is a message from "Nostur", so we change the title to "New reply"
    content.subtitle = roomTitles
    content.body = mentions.count == 1 ? (mentions.first?.message ?? "Message") : "\(mentions.count) messages" // "What's up" or "2 messages"
    content.sound = .default
    content.userInfo = ["tapDestination": "Mentions"] // For navigating to the Notifications->Mentions tab
    
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request)
}

struct Mention {
    let name: String
    let message: String
    let roomTitle: String?

    init(name: String, message: String, roomTitle: String? = nil) {
        self.name = name
        self.message = message
        self.roomTitle = roomTitle
    }
}

// Schedule a local notification for 1 direct message
func scheduleDMNotification(name: String, pubkey: String) {
#if DEBUG
    L.og.debug("scheduleDMNotification()")
#endif
    
    // Remember timestamp so we only show newer notifications next time
    UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: accountSpecificKey(pubkey, forKey: "last_dm_local_notification_timestamp"))
    
    let content = UNMutableNotificationContent()
    content.title = name // "John"
    content.body = "Direct Message"
    content.sound = .default
    content.userInfo = ["tapDestination": "Messages"] // For navigating to the DM tab
    
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request)
}

// Schedule a local notification New posts (notification bell)
// singlePostText: if there is only 1 new post we can use it as body text of notification
func scheduleNewPostNotification(_ contactsInfo: [ContactInfo], singlePostText: String? = nil) {
#if DEBUG
    L.og.debug("scheduleNewPostNotification()")
#endif
    
    // Remember timestamp so we only show newer notifications next time
    UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: "last_new_posts_local_notification_timestamp")
    
    // Create the notificatgion
    let content = UNMutableNotificationContent()
    if contactsInfo.count == 1 {
        content.title =  "New post by \(contactsInfo.map { $0.name }.formatted(.list(type: .and)))" // "New post by Jim"
        content.body = singlePostText ?? "Open in app"
    }
    else {
        content.title =  "New posts"
        content.body = "\(contactsInfo.map { $0.name }.formatted(.list(type: .and)))" // "John and Jim"
    }
    content.sound = .default
    content.userInfo = ["tapDestination": "New Posts"] // For navigating to the Notifications->Mentions tab
    
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request)
}

// Both normal completion and expiration may arrive concurrently.
final class BackgroundRefreshCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: ((Bool) -> Void)?

    init(_ completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    func finish(_ success: Bool) {
        lock.lock()
        let callback = completion
        completion = nil
        lock.unlock()
        callback?(success)
    }
}

// Cancellation can arrive before the continuation is installed, or race a relay
// response. Resume outside the lock and preserve the first result in either case.
final class BackgroundNotificationWait: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Bool?
    private var continuation: CheckedContinuation<Bool, Never>?

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return result != nil
    }

    func install(_ continuation: CheckedContinuation<Bool, Never>) {
        lock.lock()
        let result = self.result
        if result == nil { self.continuation = continuation }
        lock.unlock()
        if let result { continuation.resume(returning: result) }
    }

    func finish(_ result: Bool) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}

func checkForNotifications(accountData: AccountData) async {
    let receivedResponse = await waitForBackgroundNotifications(accountData: accountData, directMessages: false)
    guard receivedResponse, !Task.isCancelled else { return }
    await NotificationsViewModel.shared.checkForUnreadMentionsBackground(accountData: accountData)
}

func checkForDMNotifications(accountData: AccountData) async {
    _ = await waitForBackgroundNotifications(accountData: accountData, directMessages: true)
}

private func waitForBackgroundNotifications(accountData: AccountData, directMessages: Bool) async -> Bool {
    let wait = BackgroundNotificationWait()
    let subscriptionId = "BG-\(UUID().uuidString)"
    return await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
            wait.install(continuation)
            guard !wait.isFinished else { return }
            let reqTask = ReqTask(
                debounceTime: 0.05,
                timeout: 10.0,
                subscriptionId: subscriptionId,
                reqCommand: { taskId in
                    bg().perform {
                        guard !wait.isFinished else { return }
                        let since = directMessages
                            ? Int(Date.now.addingTimeInterval(-2 * 24 * 60 * 60).timeIntervalSince1970)
                            : Int(accountData.lastSeenPostCreatedAt)
                        if !directMessages { NotificationsViewModel.shared.needsUpdate = true }
                        req(RM.getMentions(pubkeys: [accountData.publicKey],
                            kinds: directMessages ? [4,1059] : [1,1111,1222,1244,20,9802,30023,34235,1311],
                            subscriptionId: taskId, since: NTimestamp(timestamp: since)))
                    }
                },
                processResponseCommand: { taskId, _, _ in
                    Backlog.shared.removeTask(with: taskId)
                    wait.finish(true)
                },
                timeoutCommand: { taskId in
                    Backlog.shared.removeTask(with: taskId)
                    wait.finish(false)
                },
                timeoutDelivery: .immediate
            )
            Backlog.shared.add(reqTask)
            // Handle cancellation between installing the continuation and add().
            if wait.isFinished {
                Backlog.shared.removeTask(with: subscriptionId)
                return
            }
            reqTask.fetch()
        }
    } onCancel: {
        wait.finish(false)
        Backlog.shared.removeTask(with: subscriptionId)
    }
}
