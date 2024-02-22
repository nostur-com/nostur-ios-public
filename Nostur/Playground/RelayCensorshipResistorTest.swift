//
//  RelayCensorshipResistorTest.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/06/2023.
//

// Relay Censorship Resistor - WIP
//1. Get all following pubkeys
//2. For Each pubkey, get write relays (from kind 3 or 10002)
//3. Group pubkeys by relays, now we have a list of relays, with pubkeys available on each relay
//4. Remove our own relay set from the list of relays
//
//A. Query these relays for new following messages
//    - A1 Create list of toQueryPubkeys, in the beginning it is equal to followingPubkeys
//    - Select Largest relay not in our relay set
//    - A2 Query relay, then subtract queried pubkeys from toQueryPubkeys
//    - A3 if toQueryPubkeys is not empty, go to next relay, subtract previous relay pubkeys from this one. repeat step A2
//
//B. When opening profile, always query a write relay that is not in our own set
import SwiftUI

struct RelayCensorshipResistorTest: View {
    
    @State var rcr:RelayCensorshipResistor? = nil
    let name = "hhu"
    
    
    var body: some View {
        VStack {
            Button("fetchRelays") {
                guard let rcr = rcr else { return }
                rcr.fetchRelays()
            }
            
            Button("pubkeysByWriteRelays") {
                guard let rcr = rcr else { return }
                print("keys: \(rcr.followingPubkeys.count)")
                print(rcr.pubkeysByWriteRelays.description)
                for (key, value) in rcr.pubkeysByWriteRelays {
                    print("\(key): \(value.count)")
                }
                rcr.getKind3or10002s()
                
                let sortedDict = rcr.pubkeysByWriteRelaysMinusOurRelaySet.sorted { $0.value.count > $1.value.count }
                
                for (key, value) in sortedDict {
                    L.og.info("📡 \(key): \(value.count)")
                }
            }
        }
        .onAppear {
            var pubkeys = NRState.shared.loggedInAccount?.followingPublicKeys ?? Set<String>()
            pubkeys.remove(NRState.shared.activeAccountPublicKey)
            
            rcr = RelayCensorshipResistor(followingPubkeys: pubkeys)
        }
    }
}


typealias RelayAddress = String

// TODO: special handling for:
// wss://nostr.mutinywallet.com
// wss://purplepag.es

class RelayCensorshipResistor {
    private var backlog = Backlog(timeout: 60, auto: true)
    public var followingPubkeys:Set<ContactPubkey>
    private var ourRelaySet:[RelayAddress] {
        let sockets = ConnectionPool.shared.connections.values
        let notNWC = sockets.filter { !$0.isNWC && !$0.isNC }
        let relayUrlStrings = notNWC.map { $0.url }
        let relayUrls = relayUrlStrings.compactMap { URL(string: $0)  }
        let ourRelaySet = relayUrls
            .filter { $0.scheme == "wss" && $0.host != nil }
            .map { "wss://\($0.host!)" }
        return ourRelaySet
    }
    
    var pubkeysByWriteRelays:[RelayAddress: Set<ContactPubkey>] = [:]
    
    var pubkeysByWriteRelaysMinusOurRelaySet:[RelayAddress: Set<ContactPubkey>] {
        pubkeysByWriteRelays.filter { !ourRelaySet.contains($0.key)  }
    }
    
    init(followingPubkeys: Set<String>) {
        self.followingPubkeys = followingPubkeys
    }
    
    @MainActor
    public func fetchRelays() {
        var pubkeys = NRState.shared.loggedInAccount?.followingPublicKeys ?? Set<String>()
        pubkeys.remove(NRState.shared.activeAccountPublicKey)
        
        let reqTask = ReqTask(debounceTime: 5.0,
                              prefix: "3-10002",
                              reqCommand: { taskId in
            req(RM.getRelays(pubkeys: Array(pubkeys), subscriptionId: taskId), relayType: .READ)
        }, processResponseCommand: { [weak self] taskId, _, _ in
            guard let self = self else { return }
            L.og.info("📡 processResponseCommand")
            self.getKind3or10002s()
        }, timeoutCommand: { [weak self] taskId in
            guard let self = self else { return }
            L.og.info("📡 timeoutCommand")
            self.getKind3or10002s()
        })
        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    public func getKind3or10002s() {
        let decoder = JSONDecoder()
        
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind IN {3,10002} AND pubkey in %@", self.followingPubkeys)
        
        bg().perform { [weak self] in
            guard let self = self else { return }
            if let kind3or10002s = try? DataProvider.shared().bg.fetch(fr) {
                L.og.info("📡 followingPubkeys: \(self.followingPubkeys.count) kind3or10002s's: \(kind3or10002s.count)")
                for k in kind3or10002s {
                    switch k.kind {
                    case 10002:
                        let rTags = k.fastTags.filter { $0.0 == "r" }
                        for r in rTags {
                            if let readOrWrite = r.2, readOrWrite == "write" {
                                guard let url = URL(string: r.1), let scheme = url.scheme,
                                      let host = url.host, scheme == "wss" else { continue }
                                
                                let key = "\(scheme)://\(host)"
                                
                                if var existingRelay = self.pubkeysByWriteRelays[key] {
                                    existingRelay.insert(k.pubkey)
                                    self.pubkeysByWriteRelays[key] = existingRelay
                                }
                                else {
                                    self.pubkeysByWriteRelays[key] = [k.pubkey]
                                }
                            }
                            
                            if r.2 == nil || r.2!.isEmpty {
                                guard let url = URL(string: r.1), let scheme = url.scheme,
                                      let host = url.host, scheme == "wss" else { continue }
                                
                                let key = "\(scheme)://\(host)"
                                
                                if var existingRelay = self.pubkeysByWriteRelays[key] {
                                    existingRelay.insert(k.pubkey)
                                    self.pubkeysByWriteRelays[key] = existingRelay
                                }
                                else {
                                    self.pubkeysByWriteRelays[key] = [k.pubkey]
                                }
                            }
                        }
                    case 3:
                        guard let content = k.content, let contentData = content.data(using: .utf8) else { continue }
                        guard let relays = try? decoder.decode(Kind3Relays.self, from: contentData) else { continue }
                        //                        if !relays.relays.isEmpty {
                        //                            L.og.info("📡 no relays for \(k.pubkey)")
                        //                        }
                        for relay in relays.relays {
                            guard let url = URL(string: relay.url), let scheme = url.scheme,
                                  let host = url.host, scheme == "wss" else { continue }
                            
                            let key = "\(scheme)://\(host)"
                            
                            if relay.readWrite.write ?? false {
                                if var existingRelay = self.pubkeysByWriteRelays[key] {
                                    existingRelay.insert(k.pubkey)
                                    self.pubkeysByWriteRelays[key] = existingRelay
                                }
                                else {
                                    self.pubkeysByWriteRelays[key] = [k.pubkey]
                                }
                            }
                        }
                    default:
                        L.og.debug("uhh")
                    }
                }
            }
        }
    }
}


struct RelayCensorshipResistorTest_Previews: PreviewProvider {
    static var previews: some View {
        RelayCensorshipResistorTest()
            .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}
