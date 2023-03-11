//
//  NotificationsManager.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/03/2023.
//

import Foundation
import CoreData

class NotificationsManager: ObservableObject {
    @Published var unreadMentions = 2
    @Published var unreadReactions = 4
    @Published var unreadZaps = 8
    
    var unread:Int {
        unreadMentions + unreadReactions + unreadZaps
    }
    
    var bgContext:NSManagedObjectContext
    var timer: Timer?
    
    init(bgContext: NSManagedObjectContext) {
        self.bgContext = bgContext
    }
    
    
    
    func checkForNewMentions() {
        
    }
    
    func checkForNewReactions() {
        
    }
    
    func checkForNewZaps() {
        
    }
    
    func checkForEverything() {
    
    }
    
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { timer in

        }
    }
    
    func stopTimer() {
        timer?.invalidate()
    }
}
