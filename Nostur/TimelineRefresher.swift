//
//  TimelineRefresher.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/01/2023.
//

import SwiftUI

struct TimelineRefresher: View {
        
        let timelineRunLoop = Timer.publish(every: 8, tolerance: 1, on: .main, in: .common).autoconnect()
        
        @State var timesFetchedWhileUnread = 0 // Increases if there are unread messages (prevent unnecessary refresh)
        @State var shouldSkipTimes = 0
        @State var isViewDisplayed = false
        
        @EnvironmentObject var ep:EventsProvider
        @EnvironmentObject var accountState:AccountState
        @EnvironmentObject var cm:ConnectionManager
        
        @State var unread = 0
        @AppStorage("lastUnreadIndex") var lastUnreadIndex = 0
        @AppStorage("lastAppearedIndex") var lastAppearedIndex = 0
        
        func fetchEventsFromFollowing(amount:Int? = 500) {
    //        let allContacts = contacts.map { $0.pubkey }
            
            for socket in cm.relaySockets {
                if (socket.relay.read || socket.relay.write) && !socket.isConnected {
                    socket.socket.connect()
                }
            }
            
            
            
            let followingPubkeys = [String](accountState.followingPublicKeys)
            cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getFollowingEvents(pubkeys: followingPubkeys, limit: amount!, since: ep.lastTimelineEventTimestamp)))
        }
        
        
        var body: some View {
            Divider()
            .onAppear {
                self.isViewDisplayed = true
                shouldSkipTimes = 0
                timesFetchedWhileUnread = 0
            }
            .onDisappear {
                self.isViewDisplayed = false
            }
            .onReceive(timelineRunLoop) { time in
                if (!isViewDisplayed) { return }
                
                print("unread is: \(unread) timesFetchedWhileUnread: \(timesFetchedWhileUnread) shouldSkipTimes: \(shouldSkipTimes)")
                
                if (unread > 0 && shouldSkipTimes > 0) {
                    shouldSkipTimes = shouldSkipTimes - 1
                    return
                }
                print("🍭🍭🍭 GONNA FETCH BABY 🍭🍭🍭🍭")
                fetchEventsFromFollowing(amount: 500)
                
                if (unread > 0) {
                    shouldSkipTimes = timesFetchedWhileUnread + shouldSkipTimes + 1
                    timesFetchedWhileUnread = timesFetchedWhileUnread + 1
                    
                    if (shouldSkipTimes > 8) {
                        shouldSkipTimes = 8
                        timesFetchedWhileUnread = 0
                        print("never skip more than 8 times")
                    }
                    else {
                        print("increase delay!")
                    }
                    
                }
                else {
                    print("delay reset")
                    shouldSkipTimes = 0
                    timesFetchedWhileUnread = 0
                }
                
                print("last timeline event timestamp: \(String(describing: ep.lastTimelineEventTimestamp?.timestamp))")
            }
        }
    }
