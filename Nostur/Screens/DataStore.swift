//
//  DataStore.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/02/2023.
//

import SwiftUI
import Foundation
import Combine

final class TimelineModel: ObservableObject, Identifiable {
    
    let eventAppeared = PassthroughSubject<Event?, Never>()
    let notesChanged = PassthroughSubject<[Event], Never>()
    let unreadCount = CurrentValueSubject<Int, Never>(0)
    var didRestoreScrollPosition = false
    
    private var lastFiveEvents:[Event] = []
    var mostRecentEvent:Event?
        
    private var subscriptions = Set<AnyCancellable>()
    private let defaults: UserDefaults
    
    var restoreScrollToId: String? {
        set { defaults.set(newValue, forKey: "restoreScrollToId-\(id)") }
        get { defaults.string(forKey: "restoreScrollToId-\(id)") }
    }
    
    var id:String = "Following"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
//        self.id = id
        
        addSubscriptions()
    }
    
    func setId(id:String) {
        self.id = id
    }
    
    func addSubscriptions() {
        
        // STORE MOST RECENT READ EVENT
        // + TRACK IF WE RESTORED YET
        eventAppeared
            .removeDuplicates()
            .throttle(for: .seconds(0.05), scheduler: RunLoop.current, latest: true)
            .compactMap { $0 }
            .sink(receiveValue: { [unowned self] appeared in
                guard self.mostRecentEvent != nil else {
                    self.mostRecentEvent = appeared
                    return
                }
                self.mostRecentEvent = self.mostRecentEvent!.created_at > appeared.created_at ? self.mostRecentEvent : appeared
            })
            .store(in: &subscriptions)
        
        // KEEP TRACK OF LAST 6 EVENTS
        // TO FETCH #E AND P's (NOT HERE)
        eventAppeared
            .removeDuplicates()
            .compactMap { $0 }
            .sink { [unowned self] event in
                self.lastFiveEvents.append(event)
                if (self.lastFiveEvents.count > 6) {
                    _ = self.lastFiveEvents.removeFirst()
                }
            }
            .store(in: &subscriptions)
        
        // AFTER 0.2 SEC OF STOP SCROLLING, WE WANT TO FETCH #E AND P (HERE)
        eventAppeared
            .removeDuplicates()
            .compactMap { $0 }
            .debounce(for: .seconds(0.5), scheduler: RunLoop.current)
            .throttle(for: .seconds(1), scheduler: RunLoop.current, latest: true)
            .sink { [unowned self] event in
//                print("🟠🟠 fetching for ids: \(ids(self.lastFiveEvents))")
//                sendNotification(.requestForJustAppeared, self.lastFiveEvents)
                
//                if (!self.didRestore.value) {
//                    self.didRestore.send(true)
//                }
//                else {
//                    self.selectedItemId = event.id
//                }
                self.restoreScrollToId = event.id
            }
            .store(in: &subscriptions)
        
        
        // WHEN NOTES ARE CHANGED, USE LAST READ INDEX TO TRACK HOW MANY UNREAD THERE ARE
        // SAVE IN self.unReadCount
        notesChanged
            .combineLatest(eventAppeared)
            .debounce(for: .seconds(0.05), scheduler: RunLoop.current)
            .map({ [unowned self] (notes, mostRecentReadEvent) in
                return (notes.filter { $0.created_at > (self.mostRecentEvent?.created_at ?? 0) })
            })
            .removeDuplicates()
            .sink(receiveValue: { [unowned self] unreadNotes in
                print("🟣🟣🟣 (notesChanged) unreadNotes.count: \(unreadNotes.count)")
                if (self.unreadCount.value != unreadNotes.count) {
                    self.objectWillChange.send()
                    self.unreadCount.send(unreadNotes.count)
                }
            })
            .store(in: &subscriptions)
    }
}


final class OnboardingTracker {
    
    let ns = NosturState.shared
    
    static public let shared = OnboardingTracker()
    
    public var pubkey:String = NosturState.GUEST_ACCOUNT_PUBKEY // Onboard for which pubkey?
    
    // Fill from kind.3 and use Timeline.onAppear (while onboarding).
    // So we dont have to wait for kind0 for every p and Account.addToFollows
    public var followingKeys:[String] = []
    
    public var isOnboarding:Bool {
        didStartOnboarding == true &&
        (didFetchKind0 == false ||
         didFetchKind3 == false ||
         didAddFollowers == false ||
         didFillTimeline == false)
    }
    
    public var didStartOnboarding = false {
        didSet {
            print("✈️✈️✈️✈️ didStartOnboarding: \(didStartOnboarding)")
        }
    }
    public var didFetchKind0 = false {
        didSet { print("✈️✈️✈️✈️ didFetchKind0: \(didFetchKind0)") }
    }
    public var didFetchKind3 = false {
        didSet { print("✈️✈️✈️✈️ didFetchKind3: \(didFetchKind3)") }
    }
    public var didAddFollowers = false {
        didSet { print("✈️✈️✈️✈️ didAddFollowers: \(didAddFollowers)") }
    }
    public var didFillTimeline = false {
        didSet {
            if (didFillTimeline) {
                ns.onBoardingIsShown = false
            }
            print("✈️✈️✈️✈️ didFillTimeline: \(didFillTimeline)")
        }
    }
    
    public func startOnboarding(pubkey:String) {
//        DataStore.shared.unreadCount.send(0)
        self.pubkey = pubkey
        self.didStartOnboarding = true
        self.followingKeys = []
        self.didFetchKind0 = false
        self.didFetchKind3 = false
        self.didAddFollowers = false
        self.didFillTimeline = false
    }
}


final class SideBarModel: ObservableObject {
    @Published var showSidebar = false
}
