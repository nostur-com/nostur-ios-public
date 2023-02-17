//
//  CleanTimeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/02/2023.
//

import SwiftUI

extension CleanTimeline {
    struct IsolatedStuff: View {
        
//        static func == (lhs: CleanTimeline.IsolatedStuff, rhs: CleanTimeline.IsolatedStuff) -> Bool {
//            return true
//        }
        
        @FetchRequest(entity: Event.entity(), sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)], predicate: NSPredicate(value: false))
        private var events:FetchedResults<Event>
        
        var computedEvents:[Event] {
            get {
                events.reversed()
            }
        }
        var body: some View {
            let _ = Self._printChanges()
            VStack {
                Text(String(events.nsPredicate?.description.prefix(50) ?? ""))
                
                
                Spacer()
            }
            .onReceive(receiveNotification(.activeAccountChanged)) { notification in
                let pubkeys = (notification.object as! Account).follows?.map { $0.pubkey! } ?? []
                events.nsPredicate = NSPredicate(format: "kind IN {1,6} AND pubkey IN %@", pubkeys)
            }
        }
    }
}

struct CleanTimeline: View {
    
    
    
    
    var body: some View {
        let _ = Self._printChanges()
        
        
        SideView()
        
        IsolatedStuff()
        
            
//            .onChange(of: ns.followingPublicKeys) { newValue in
//                updateTimeline()
//            }
    }
}

struct SideView: View {
    @EnvironmentObject var ns:NosturState
    
    func updateTimeline() {
        if (ns.account != nil) {
            sendNotification(.activeAccountChanged, ns.account!)
        }
    }
    
    func switchToFirstAccount() {
        ns.setAccount(account: ns.accounts.first)
    }
    
    func switchToLastAccount() {
        ns.setAccount(account: ns.accounts.last)
    }
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
            Text("Account: \(ns.account?.name ?? "(none)")")
        }
        HStack {
            Text("First account").onTapGesture {
                switchToFirstAccount()
                updateTimeline()
            }
            .foregroundColor(.red)
            Text("Last account").onTapGesture {
                switchToLastAccount()
                updateTimeline()
            }
            .foregroundColor(.green)
            Text("Update").onTapGesture { updateTimeline() }
        }
        .onAppear {
            updateTimeline()
        }
    }
}



struct CleanTimeline_Previews: PreviewProvider {
    static var previews: some View {
        CleanTimeline()
            .withPreviewEnvironment()
    }
}
