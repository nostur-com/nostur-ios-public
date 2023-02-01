//
//  SocketPool.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/01/2023.
//

import Foundation
import Starscream

class SocketPool: WebSocketDelegate, ObservableObject {
    
    static let shared = SocketPool()

    var socketQueue = DispatchQueue(label: "nostur.queue", qos: .background)
    @Published var sockets:[String : SocketClient] = [:]
    
    func addSocket(url:String, read:Bool = true, write: Bool = false) -> SocketClient {
        if (!sockets.keys.contains(url)) {
            
            var request = URLRequest(url: URL(string: url)!)
            request.timeoutInterval = 5
            
//            Compression gives error: WSError(type: Starscream.ErrorType.protocolError, message: "not valid UTF-8 data", code: 1002)
//            let compression = WSCompression()
//            let socket = WebSocket(request: request, compressionHandler: compression)
            
            let socket = WebSocket(request: request)
            socket.callbackQueue = self.socketQueue
            socket.delegate = self
            socket.connect()
            
            let socketClient = SocketClient(client: socket, read: read, write: write)
            sockets[url] = socketClient
            return socketClient
        }
        else {
            return sockets[url]!
        }
    }
    
    func isUrlConnected(_ url:String) -> Bool {
        if (!sockets.keys.contains(url)) { return false }
        if let socket:SocketClient = sockets[url] {
            return socket.isConnected
        }
        return false
    }
    
    func connectSocketByUrl(_ url:String) {
        if let socket:SocketClient = sockets[url] {
            socket.client.connect()
        }
    }
    
    func disconnectSocketByUrl(_ url:String) {
        if let socket:SocketClient = sockets[url] {
            socket.client.disconnect()
            socket.isConnected = false
        }
    }
    
    func removeSocket(url:String) {
        if (sockets.keys.contains(url)) {
            sockets.removeValue(forKey: url)
        }
    }
    
    func sendMessage(_ message:ClientMessage) {
        print("🔴🔴🔴🔴🔴🔴🔴🔴 sendMessage DISABLED FOR DEV 🔴🔴🔴🔴🔴🔴")
        print("🔴🔴🔴🔴🔴🔴🔴🔴 sendMessage DISABLED FOR DEV 🔴🔴🔴🔴🔴🔴")
        print("🔴🔴🔴🔴🔴🔴🔴🔴 sendMessage DISABLED FOR DEV 🔴🔴🔴🔴🔴🔴")
        print("🔴🔴🔴🔴🔴🔴🔴🔴 sendMessage DISABLED FOR DEV 🔴🔴🔴🔴🔴🔴")
        print("🔴🔴🔴🔴🔴🔴🔴🔴 sendMessage DISABLED FOR DEV 🔴🔴🔴🔴🔴🔴")
        return
        print("⬆ Sending: \(String(message.message.prefix(260)))")
        for (url, socketClient) in sockets {
            if (!socketClient.isConnected) { socketClient.client.connect() }
            
            if message.type == .REQ || message.type == .CLOSE { // REQ AND CLOSE IS FOR ALL RELAYS
                socketClient.client.write(string: message.message) { }
            }
            else if message.type == .EVENT && socketClient.write { // EVENT IS ONLY FOR WRITE RELAYS
                print("🟢 PUBLISHING TO \(url): \(message.message)")
                socketClient.client.write(string: message.message) { }
            }
        }
    }
    
    func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocket) {
        if let socketClient = sockets[client.request.url!.absoluteString] {
            
            switch event {
            case .connected(let headers):
                socketClient.isConnected = true
                print("websocket is connected: \(headers)")
            case .disconnected(let reason, let code):
                socketClient.isConnected = false
                print("websocket is disconnected: \(reason) with code: \(code)")
            case .text(let string):
//                print("💬 Received text: \(string)")
                MessageParser.shared.socketReceivedMessage(text: string)
            case .binary(let data):
                print("Received data: \(data.count)")
            case .ping(_):
                break
            case .pong(_):
                break
            case .viabilityChanged(_):
                break
            case .reconnectSuggested(_):
                break
            case .cancelled:
                socketClient.isConnected = false
            case .error(let error):
                socketClient.isConnected = false
                print(error!)
            }
            
        }
    }
    
}

class SocketClient: ObservableObject {
    var client:WebSocket
    @Published var isConnected = false
    @Published var read = true
    @Published var write = false
    
    init(client: WebSocket, isConnected: Bool = false, read: Bool = true, write: Bool = false) {
        self.client = client
        self.isConnected = isConnected
        self.read = read
        self.write = write
    }
}





