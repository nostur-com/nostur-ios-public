//
//  NewPostNotifier.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/11/2023.
//

import SwiftUI
import NostrEssentials

// PLAN:
// Reads which pubkeys we want new post notifications for from iCloud table
// Checks for any new post AFTER .lastCheckDate
// Creates notification if there are new posts
// Store notification .createdAt as .lastCheckDate
// Repeat

// Tapping notification should go to special pubkeys feed, just showing all posts. Maybe single pubkey LVM. Or ProfilePostsView
class NewPostNotifier: ObservableObject {
    
    static let shared = NewPostNotifier()
    
    @Published var enabledPubkeys:Set<String> = []
    
    // Needed as fallback if account() doesn't resolve yet
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""

    private var backlog = Backlog(timeout: 10.0, auto: true)
    private var lastCheck:Date? = nil
    
    private init() {
        
    }
    
    @MainActor
    public func reload() {
        self.load()
    }
    
    private func load() {
        L.og.debug("NewPostNotifier.load()")
        let tasks = CloudTask.fetchAll(byType: .notifyOnPosts, andAccountPubkey: account()?.publicKey ?? activeAccountPublicKey)
        enabledPubkeys = Set(tasks.compactMap { $0.value_ })
    }
    
    
    @MainActor
    public func runCheck() {
        guard !NRState.shared.appIsInBackground else { L.lvm.debug("NewPostNotifier.runCheck(): skipping, app in background."); return }
        L.og.debug("NewPostNotifier.runCheck()")
        if let lastCheck = lastCheck {
            guard (Date.now.timeIntervalSince1970 - lastCheck.timeIntervalSince1970) > 60
            else {
                L.og.debug("NewPostNotifier.runCheck() - too soon, waiting a bit")
                return
            }
        }
        let accountPubkey = account()?.publicKey ?? activeAccountPublicKey
        let tasks = CloudTask.fetchAll(byType: .notifyOnPosts, andAccountPubkey: accountPubkey)
        enabledPubkeys = Set(tasks.compactMap { $0.value_ })
        
        // since = "lastCheck" ?? "most recent notification" ?? "most recent task" ?? "8 hours ago"
        let since = (self.lastCheck?.timeIntervalSince1970 ?? (PersistentNotification.fetchPersistentNotification(byPubkey: accountPubkey, type: .newPosts)?.createdAt.timeIntervalSince1970 ?? tasks.first?.createdAt.timeIntervalSince1970)) ?? (Date.now.timeIntervalSince1970 - (3600 * 8))
        
        let task = ReqTask(
            debounceTime: 0.5,
            subscriptionId: "NP",
            reqCommand: { [weak self] taskId in
                guard let self else { return }
                if let cm = NostrEssentials
                    .ClientMessage(type: .REQ,
                                   subscriptionId: taskId,
                                   filters: [
                                    Filters(
                                        authors: self.enabledPubkeys,
                                        kinds: PROFILE_KINDS,
                                        since: Int(since),
                                        limit: 250
                                    )
                                   ]
                    ).json() {
                    self.lastCheck = .now
                    req(cm)
                }
                else {
                    L.og.info("NewPostNotifier: unable to create REQ")
                }
            },
            processResponseCommand: { [weak self] taskId, relayMessage, event in
                guard let self else { return }
                self.backlog.clear()
                bg().perform { [weak self] in
                    guard let self else { return }
                    let fr = Event.fetchRequest()
                    fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                    fr.predicate = NSPredicate(format: "created_at >= %i AND pubkey IN %@ AND kind IN %@ AND flags != \"is_update\"", Int(since), self.enabledPubkeys, PROFILE_KINDS)
                    if let newPosts = try? bg().fetch(fr), !newPosts.isEmpty {
                        self.createNewPostsNotification(newPosts, accountPubkey: accountPubkey)
                    }
                }
            },
            timeoutCommand: { [weak self] taskId in
                guard let self else { return }
                self.backlog.clear()
                L.og.debug("NewPostNotifier.runCheck(): timeout")
                bg().perform { [weak self] in
                    guard let self else { return }
                    let fr = Event.fetchRequest()
                    fr.predicate = NSPredicate(format: "created_at >= %i AND pubkey IN %@ AND kind IN %@ AND flags != \"is_update\"", Int(since), self.enabledPubkeys, PROFILE_KINDS)
                    if let newPosts = try? bg().fetch(fr), !newPosts.isEmpty {
                        self.createNewPostsNotification(newPosts, accountPubkey: accountPubkey)
                    }
                }
            })
        backlog.add(task)
        task.fetch()
    }
    
    @MainActor
    public func isEnabled(for pubkey: String) -> Bool {
        return enabledPubkeys.contains(pubkey)
    }
    
    @MainActor
    public func toggle(_ pubkey: String) {
        if enabledPubkeys.contains(pubkey) {
            disable(pubkey)
        }
        else {
            enable(pubkey)
        }
    }
    
    private func enable(_ pubkey: String) {
        enabledPubkeys.insert(pubkey)
        let accountPubkey = account()?.publicKey ?? activeAccountPublicKey
        let task = CloudTask.new(ofType: .notifyOnPosts, andValue: pubkey, date: .now)
        task.accountPubkey_ = accountPubkey
        save()
    }
    
    private func disable(_ pubkey: String) {
        enabledPubkeys.remove(pubkey)
        let accountPubkey = account()?.publicKey ?? activeAccountPublicKey
        if let task = CloudTask.fetchTask(byType: .notifyOnPosts, andPubkey: pubkey, andAccountPubkey: accountPubkey) {
            context().delete(task)
            save()
        }
    }
    
    private func createNewPostsNotification(_ newPosts:[Event], accountPubkey: String) {
        L.og.debug("NewPostNotifier.createNewPostsNotification: newPosts: \(newPosts.count)")
        let contacts = Contact.fetchByPubkeys(newPosts.map { $0.pubkey }).map { ContactInfo(name: $0.anyName, pubkey: $0.pubkey, pfp: $0.picture) }
        // Checking existing unread new posts notification(s), merge them into a new one, delete older.
        let existing = PersistentNotification.fetchUnreadNewPostNotifications(accountPubkey: accountPubkey)
        let allContacts:[ContactInfo] = existing.reduce(contacts) { partialResult, notification in
            return (partialResult + notification.contactsInfo)
        }
        let existingSince = existing.last?.since ?? Int64(existing.last?.createdAt.timeIntervalSince1970 ?? 0)
        let newPostsSince = newPosts.sorted(by: { $0.created_at > $1.created_at }).last?.created_at ?? 0
        let since = existingSince < newPostsSince && existingSince != 0 ? existingSince : newPostsSince
        for notification in existing {
            context().delete(notification)
        }
        let newPostNotification = PersistentNotification.createNewPostsNotification(pubkey: accountPubkey, contacts: Array(Set(allContacts)), since: since)
        NotificationsViewModel.shared.checkNeedsUpdate(newPostNotification)
    }
}
//
//struct NewPostsNotificationData: Codable {
//    let contacts:[ContactInfo]
//    
//    public var pubkeys:[String] {
//        contacts.map { $0.pubkey }
//    }
//}

struct ContactInfo: Codable, Identifiable, Hashable, Equatable {
    var id:String { pubkey }
    let name:String
    let pubkey:String
    var pfp:String?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(pubkey)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pubkey == rhs.pubkey
    }
    
}
