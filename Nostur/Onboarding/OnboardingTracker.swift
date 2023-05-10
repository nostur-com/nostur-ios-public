////
////  OnboardingTracker.swift
////  Nostur
////
////  Created by Fabian Lachman on 27/03/2023.
////
//
//import SwiftUI
//import Foundation
//import Combine
//
//final class OnboardingTracker {
//    
//    static public let shared = OnboardingTracker()
//    
//    public var pubkey:String = NosturState.GUEST_ACCOUNT_PUBKEY // Onboard for which pubkey?
//    
//    // Fill from kind.3 and use Timeline.onAppear (while onboarding).
//    // So we dont have to wait for kind0 for every p and Account.addToFollows
//    public var followingKeys:[String] = []
//    
//    public var isOnboarding:Bool {
//        didStartOnboarding == true &&
//        (didFetchKind0 == false ||
//         didFetchKind3 == false ||
//         didAddFollowers == false ||
//         didFillTimeline == false)
//    }
//    
//    public var didStartOnboarding = false {
//        didSet {
//            print("✈️✈️✈️✈️ didStartOnboarding: \(didStartOnboarding)")
//        }
//    }
//    public var didFetchKind0 = false {
//        didSet { print("✈️✈️✈️✈️ didFetchKind0: \(didFetchKind0)") }
//    }
//    public var didFetchKind3 = false {
//        didSet { print("✈️✈️✈️✈️ didFetchKind3: \(didFetchKind3)") }
//    }
//    public var didAddFollowers = false {
//        didSet { print("✈️✈️✈️✈️ didAddFollowers: \(didAddFollowers)") }
//    }
//    public var didFillTimeline = false {
//        didSet {
//            if (didFillTimeline) {
//                sendNotification(.endOnboarding)
//            }
//            print("✈️✈️✈️✈️ didFillTimeline: \(didFillTimeline)")
//        }
//    }
//    
//    public func startOnboarding(pubkey:String) {
////        DataStore.shared.unreadCount.send(0)
//        self.pubkey = pubkey
//        self.didStartOnboarding = true
//        self.followingKeys = []
//        self.didFetchKind0 = false
//        self.didFetchKind3 = false
//        self.didAddFollowers = false
//        self.didFillTimeline = false
//    }
//}
//
//
//
