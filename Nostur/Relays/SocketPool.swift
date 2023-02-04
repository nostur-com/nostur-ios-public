////
////  SocketPool.swift
////  Nostur
////
////  Created by Fabian Lachman on 29/01/2023.
////
//
//import Foundation
//import Starscream
//import CoreData
//
//class SocketPool: WebSocketDelegate, ObservableObject {
//    
//    static let shared = SocketPool()
//
//    var socketQueue = DispatchQueue(label: "nostur.queue", qos: .background)
//    
//    @Published var sockets:[NSManagedObjectID : SocketClient] = [:]
//    
//    func addSocket(relayId:NSManagedObjectID, url:String, read:Bool = true, write: Bool = false) -> SocketClient {
//        if (!sockets.keys.contains(relayId)) {
//            
//            var request = URLRequest(url: URL(string: url)!)
////            request.setValue(["wamp"].joined(separator: ","), forHTTPHeaderField: "Sec-WebSocket-Protocol")
//            request.timeoutInterval = 15
//            
//            //Compression gives error: WSError(type: Starscream.ErrorType.protocolError, message: "not valid UTF-8 data", code: 1002)
////            let compression = WSCompression()
////            let socket = WebSocket(request: request, compressionHandler: compression)
//            
//            let socket = WebSocket(request: request, compressionHandler: .none)
//            socket.callbackQueue = self.socketQueue
//            socket.delegate = self
//            let socketClient = SocketClient(client: socket, read: read, write: write, relayId: relayId)
//            if (read || write) {
//                socketClient.isConnecting = true
//                socket.connect()
//            }
//            sockets[relayId] = socketClient
//            return socketClient
//        }
//        else {
//            return sockets[relayId]!
//        }
//    }
//    
//    func socketByUrl(_ url:String) -> SocketClient? {
//        let managedSocket = sockets.filter { relayId, managedSocket in
//            return managedSocket.client.request.url!.absoluteString.lowercased() == url.lowercased()
//        }.first?.value
//        
//        guard managedSocket != nil, let socketClient = managedSocket else {
//            return nil
//        }
//        return socketClient
//    }
//    
//    func isUrlConnected(_ url:String) -> Bool {
//        let managedSocket = sockets.filter { relayId, managedSocket in
//            return managedSocket.client.request.url!.absoluteString.lowercased() == url.lowercased()
//        }.first?.value
//        guard managedSocket != nil, let socketClient = managedSocket else {
//            return false
//        }
//        return socketClient.isConnected
//    }
//    
//    func removeSocket(_ relayId:NSManagedObjectID) {
//        if (sockets.keys.contains(relayId)) {
//            sockets.removeValue(forKey: relayId)
//        }
//    }
//    
//    func sendMessage(_ message:ClientMessage) {
//        for (relayId, socketClient) in sockets {
//            guard socketClient.read || socketClient.write else {
//                // Skip if relay is not selected for reading or writing events
//                continue
//            }
//            
//            if message.type == .REQ && socketClient.read { // REQ FOR ALL READ RELAYS
//                if (!socketClient.isConnected && !socketClient.isConnecting) {
//                    socketClient.client.connect()
//                }
////                print("⬇️⬇️ REQUESTING: \(String(message.message.prefix(260)))")
//                socketClient.client.write(string: message.message)
//            }
//            else if  message.type == .CLOSE { // CLOSE FOR ALL RELAYS
//                if (!socketClient.isConnected && socketClient.read && !socketClient.isConnecting) {
//                    socketClient.client.connect()
//                }
////                print("🔚🔚 CLOSE: \(String(message.message.prefix(260)))")
//                socketClient.client.write(string: message.message) { }
//            }
//            else if message.type == .EVENT && socketClient.write { // EVENT IS ONLY FOR WRITE RELAYS
//                if (!socketClient.isConnected && !socketClient.isConnecting) {
//                    socketClient.client.connect()
//                }
//                print("⬆⬆⬆ PUBLISHING TO \(socketClient.client.request.url!.description): \(message.message)")
//                socketClient.client.write(string: message.message) { }
//            }
//        }
//    }
//    
//    func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocket) {
//        let managedSocket = sockets.filter { relayId, managedSocket in
//            return managedSocket.client.request.url!.absoluteString == client.request.url!.absoluteString
//        }.first?.value
//        guard managedSocket != nil, let socketClient = managedSocket else {
//            print("🔌 🔴 Received from socket that is not in .sockets")
//            return
//        }
//        switch event {
//        case .connected(let headers):
//            print(headers.description)
//            DispatchQueue.main.async {
//                socketClient.isConnecting = false
//                socketClient.isConnected = true
//            }
//            print("🔌 CONNECTED \(socketClient.client.request.description): \(headers)")
//        case .disconnected(let reason, let code):
//            DispatchQueue.main.async {
//                socketClient.isConnecting = false
//                socketClient.isConnected = false
//            }
//            print("🔌 DISCONNECTED \(socketClient.client.request.description): \(reason) with code: \(code)")
//        case .text(let string):
////                print("🔌 💬 Received text: \(string)")
//            MessageParser.shared.socketReceivedMessage(text: string)
//        case .binary(let data):
//            print("🔌 RECEIVED DATA \(socketClient.client.request.description): \(data.count)")
//        case .ping(_):
//            break
//        case .pong(_):
//            break
//        case .viabilityChanged(_):
//            break
//        case .reconnectSuggested(_):
//            break
//        case .cancelled:
//            DispatchQueue.main.async {
//                socketClient.isConnecting = false
//                socketClient.isConnected = false
//            }
//            print("🔌 CANCELLED \(socketClient.client.request.description)")
//        case .error(let error):
//            DispatchQueue.main.async {
//                socketClient.isConnecting = false
//                socketClient.isConnected = false
//            }
//                print("🔌🔴 ERROR \(socketClient.client.request.description): \(error!)")
//        }
//    }
//    
//}
//
//class SocketClient: ObservableObject {
//    var client:WebSocket
//    var isConnecting = false
//    @Published var isConnected = false
//    @Published var read = true
//    @Published var write = false
//    var relayId:NSManagedObjectID
//    
//    init(client: WebSocket, isConnected: Bool = false, read: Bool = true, write: Bool = false, relayId:NSManagedObjectID) {
//        self.client = client
//        self.isConnecting = false
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
