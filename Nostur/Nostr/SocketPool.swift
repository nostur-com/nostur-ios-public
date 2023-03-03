//
//  SocketPool.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/01/2023.
//

import Foundation
import Starscream
import CoreData
import OSLog

// Structure is:
// SocketPool
//  .sockets
//      [NSManagedObjectID] = ManagedClient
//                                    .client
//                                    .activeSubscriptions
//
//      [NSManagedObjectID] = ManagedClient
//                                    .client
//                                    .activeSubscriptions
//
//      [NSManagedObjectID] = ManagedClient
//                                    .client
//                                    .activeSubscriptions
//
//      [NSManagedObjectID] = ManagedClient
//                                    .client
//                                    .activeSubscriptions

final class SocketPool: ObservableObject {
    
    static let shared = SocketPool()
    
    var socketQueue = DispatchQueue(label: "nostur.queue", qos: .background)
    
    @Published var sockets:[NSManagedObjectID : ManagedClient] = [:]
    
    func connectAll() {
        for socket in sockets {
            if !socket.value.isConnecting && !socket.value.isConnected {
                socket.value.client.connect()
            }
        }
    }
    
    func addSocket(relayId:NSManagedObjectID, url:String, read:Bool = true, write: Bool = false) -> ManagedClient {
        if (!sockets.keys.contains(relayId)) {
            
            var request = URLRequest(url: URL(string: url)!)
//             request.setValue(["wamp"].joined(separator: ","), forHTTPHeaderField: "Sec-WebSocket-Protocol")

            request.timeoutInterval = 15
            
            let client = WebSocket(request: request)
            client.callbackQueue = self.socketQueue
            
            let managedClient = ManagedClient(relayId: relayId, url: url, client:client, read: read, write: write)
            
            if (read || write) {
                managedClient.connect()
            }
            sockets[relayId] = managedClient
            return managedClient
        }
        else {
            return sockets[relayId]!
        }
    }
    
    func socketByUrl(_ url:String) -> ManagedClient? {
        let managedClient = sockets.filter { relayId, managedClient in
            managedClient.url == url.lowercased()
        }.first?.value
        return managedClient
    }
    
    func isUrlConnected(_ url:String) -> Bool {
        let managedClient = sockets.filter { relayId, managedClient in
            managedClient.url == url.lowercased()
        }.first?.value
        guard managedClient != nil else {
            return false
        }
        return managedClient!.isConnected
    }
    
    func removeSocket(_ relayId:NSManagedObjectID) {
        if (sockets.keys.contains(relayId)) {
            sockets.removeValue(forKey: relayId)
        }
    }
    
    func sendMessage(_ message:ClientMessage, subscriptionId:String? = nil) {
//        if (message.type == .REQ) {
//            let read = sockets.values.filter { $0.read == true }.count
//            print("⬇️⬇️ REQ ON \(read) RELAYS: \(String(message.message.prefix(260)))")
//        }
        
        Task(priority: .background) {
            for (_, managedClient) in sockets {
//                print("active subscriptions \(managedClient.url): \(managedClient.activeSubscriptions.count)")
                guard managedClient.read || managedClient.write else {
                    // Skip if relay is not selected for reading or writing events
                    continue
                }
                
                if message.type == .REQ && managedClient.read { // REQ FOR ALL READ RELAYS
                    if (!managedClient.isConnected) && (!managedClient.isConnecting) {
                        managedClient.connect()
                    }
                    // skip if we already have an active subcription
                    guard subscriptionId == nil || managedClient.activeSubscriptions.firstIndex(where: { $0 == subscriptionId }) == nil else { continue }
                    if (subscriptionId != nil) {
                        print("⬇️⬇️ ADDED SUBSCRIPTION  \(managedClient.url): \(subscriptionId!)")
                        managedClient.activeSubscriptions.append(subscriptionId!)
                    }
//                    print("REQUESTING: \(String(message.message.prefix(260)))")
//                    print("⬇️⬇️ REQUESTING: \(String(message.message))")
                    managedClient.client.write(string: message.message)
                }
                else if  message.type == .CLOSE { // CLOSE FOR ALL RELAYS
                    if (!managedClient.isConnected && managedClient.read) && (!managedClient.isConnecting) {
                        managedClient.connect()
                    }
//                    print("🔚🔚 CLOSE: \(String(message.message.prefix(260)))")
                    managedClient.client.write(string: message.message) { }
                }
                else if message.type == .EVENT && managedClient.write { // EVENT IS ONLY FOR WRITE RELAYS
                    if (!managedClient.isConnected) && (!managedClient.isConnecting) {
                        managedClient.connect()
                    }
                    print("🚀🚀🚀 PUBLISHING TO \(managedClient.url): \(message.message)")
                    managedClient.client.write(string: message.message) { }
                }
            }
        }
    }
    
    func removeActiveFollowingSubscriptions() {
        for socket in sockets {
            socket.value.activeSubscriptions.removeAll { subscriptionId in
                subscriptionId == "Following"
            }
        }
    }
}

class ManagedClient: WebSocketDelegate, ObservableObject {
    
    var relayId:NSManagedObjectID
    var url:String
    var client:WebSocket
    
    var isConnecting = false
    @Published var isConnected = false
    @Published var read = true
    @Published var write = false
    
    var activeSubscriptions:[String] = []
    
    init(relayId: NSManagedObjectID, url: String, client:WebSocket, read: Bool = true, write: Bool = false) {
        self.relayId = relayId
        self.url = url.lowercased()
        self.read = read
        self.write = write
        self.client = client
        self.client.delegate = self
    }
    
    func connect() {
        self.isConnecting = true
        self.client.connect()
    }
    
    func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) {
        switch event {
        case .connected(let _):
//            print(headers.description)
            DispatchQueue.main.async {
                self.isConnecting = false
                self.isConnected = true
            }
                self.activeSubscriptions = []
                print("🔌 CONNECTED \(self.url)")
//                print("🔌 CONNECTED \(self.url): \(headers)")
        case .disconnected(let reason, let code):
            DispatchQueue.main.async {
                self.isConnecting = false
                self.isConnected = false
            }
                self.activeSubscriptions = []
                print("🔌 DISCONNECTED \(self.url): \(reason) with code: \(code)")
        case .text(let string):
//                print("🔌 💬 Received text: \(string)")
            MessageParser.shared.socketReceivedMessage(text: string, relayUrl: self.url)
        case .binary(let data):
                print("🔌 RECEIVED DATA \(self.url): \(data.count)")
        case .ping(_):
            break
        case .pong(_):
            break
        case .viabilityChanged(_):
            break
        case .reconnectSuggested(_):
            break
        case .cancelled:
            DispatchQueue.main.async {
                self.isConnecting = false
                self.isConnected = false
            }
                self.activeSubscriptions = []
                print("🔌 CANCELLED \(self.url)")
        case .error(let error):
            DispatchQueue.main.async {
                self.isConnecting = false
                self.isConnected = false
            }
                self.activeSubscriptions = []
                print("🔌🔴 ERROR \(self.url): \(error!)")
        }
    }
}



