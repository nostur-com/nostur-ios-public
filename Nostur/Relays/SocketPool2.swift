////
////  SocketPool2.swift
////  Nostur
////
////  Created by Fabian Lachman on 04/02/2023.
////
//
//import Foundation
//import Starscream
//import CoreData
//
//class SocketPool: WebSocketConnectionDelegate, ObservableObject {
//
//    static let shared = SocketPool()
//
////    var socketQueue = DispatchQueue(label: "nostur.queue", qos: .background)
//    
//    @Published var sockets:[NSManagedObjectID : ManagedConnection] = [:]
//    
//    func addSocket(relayId:NSManagedObjectID, url:String, read:Bool = true, write: Bool = false) -> ManagedConnection {
//        if (!sockets.keys.contains(relayId)) {
//            
//            let wsc = WebSocketTaskConnection(url: URL(string: url)!, relayId: relayId)
//            wsc.delegate = self
//                        
//            let managedConnection = ManagedConnection(connection: wsc, read: read, write: write, relayId: relayId)
//            if (read || write) {
//                wsc.connect()
//            }
//            sockets[relayId] = managedConnection
//            return managedConnection
//        }
//        else {
//            return sockets[relayId]!
//        }
//    }
//    
//    func managedConnectionByUrl(_ url:String) -> ManagedConnection? {
//        let managedConnection = sockets.filter { relayId, managedConnection in
//            return managedConnection.url == url.lowercased()
//        }.first?.value
//        guard managedConnection != nil else {
//            return nil
//        }
//        return managedConnection
//    }
//    
//    func isUrlConnected(_ url:String) -> Bool {
//        let managedConnection = sockets.filter { relayId, managedConnection in
//            return managedConnection.url == url.lowercased()
//        }.first?.value
//        guard managedConnection != nil else {
//            return false
//        }
//        return managedConnection!.isConnected
//    }
//    
//    func removeSocket(_ relayId:NSManagedObjectID) {
//        if (sockets.keys.contains(relayId)) {
//            sockets.removeValue(forKey: relayId)
//        }
//    }
//    
//    func sendMessage(_ message:ClientMessage) {
//        for (_, managedConnection) in sockets {
//            guard managedConnection.read || managedConnection.write else {
//                // Skip if relay is not selected for reading or writing events
//                continue
//            }
//            
//            if message.type == .REQ && managedConnection.read { // REQ FOR ALL READ RELAYS
//                if (!managedConnection.isConnected) {
//                    managedConnection.connection.connect()
//                }
////                print("⬇️⬇️ REQUESTING: \(String(message.message.prefix(260)))")
//                managedConnection.connection.send(text: message.message)
//            }
//            else if  message.type == .CLOSE { // CLOSE FOR ALL RELAYS
//                if (!managedConnection.isConnected && managedConnection.read) {
//                    managedConnection.connection.connect()
//                }
////                print("🔚🔚 CLOSE: \(String(message.message.prefix(260)))")
//                managedConnection.connection.send(text: message.message)
//            }
//            else if message.type == .EVENT && managedConnection.write { // EVENT IS ONLY FOR WRITE RELAYS
//                if (!managedConnection.isConnected) {
//                    managedConnection.connection.connect()
//                }
//                print("⬆⬆⬆ PUBLISHING TO \(managedConnection.url): \(message.message)")
//                managedConnection.connection.send(text: message.message)
//            }
//        }
//    }
//    
//    func managedConnectionForConnection(_ connection: WebSocketConnection) -> ManagedConnection? {
//        let managedConnection = sockets.filter { relayId, managedConnection in
//            return managedConnection.relayId == connection.relayId
//        }.first?.value
//        return managedConnection
//    }
//    
//    func onConnected(connection: WebSocketConnection) {
//        guard let managedConnection = managedConnectionForConnection(connection) else {
//            return
//        }
//        DispatchQueue.main.async {
//            managedConnection.isConnected = true
//        }
//        print("🔌 CONNECTED \(managedConnection.url)")
//    }
//    
//    func onDisconnected(connection: WebSocketConnection, error: Error?) {
//        guard let managedConnection = managedConnectionForConnection(connection) else {
//            return
//        }
//        DispatchQueue.main.async {
//            managedConnection.isConnected = false
//        }
//        print("🔌 DISCONNECTED \(managedConnection.url) \(error ?? "")")
//    }
//    
//    func onError(connection: WebSocketConnection, error: Error) {
//        guard let managedConnection = managedConnectionForConnection(connection) else {
//            return
//        }
//        DispatchQueue.main.async {
//            managedConnection.isConnected = false
//        }
//        print("🔌🔴 ERROR \(managedConnection.url) \(error)")
//    }
//    
//    func onMessage(connection: WebSocketConnection, text: String) {
////        print("🔌 💬 Received text: \(text)")
//        MessageParser.shared.socketReceivedMessage(text: text)
//    }
//    
//    func onMessage(connection: WebSocketConnection, data: Data) {
//        guard let managedConnection = managedConnectionForConnection(connection) else {
//            return
//        }
//        print("🔌 RECEIVED DATA \(managedConnection.url): \(data.count)")
//    }
//    
//}
//
//class ManagedConnection: ObservableObject {
//    var connection:WebSocketTaskConnection
////    var isConnecting = false
//    @Published var isConnected = false
//    @Published var read = true
//    @Published var write = false
//    var relayId:NSManagedObjectID
//    var url:String {
//        get {
//            connection.url
//        }
//    }
//    
//    init(connection: WebSocketTaskConnection, isConnected: Bool = false, read: Bool = true, write: Bool = false, relayId:NSManagedObjectID) {
//        self.connection = connection
////        self.isConnecting = false
//        self.isConnected = isConnected
//        self.read = read
//        self.write = write
//        self.relayId = relayId
//    }
//}
//
//
//
//
//
