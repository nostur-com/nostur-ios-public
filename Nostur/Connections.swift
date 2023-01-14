//
//  Connections.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/01/2023.
//

import SwiftUI
import CoreData
import Foundation
import Starscream
//import NostrKit
import SwiftyJSON

public protocol EventDelegate {
    func didReceiveEvent(text: String)
}

class RelaySocket : WebSocketDelegate {
    var delegate: EventDelegate
    var relay: Relay
    
    var socket: WebSocket!
    var isConnected = false
    
    init(relay: Relay, delegate: EventDelegate) {
        self.relay = relay
        self.delegate = delegate
    }
    
    func connect(relayURL:String? = nil) {
        var request = URLRequest(url: URL(string: relayURL ?? relay.url!)!)
        request.timeoutInterval = 20
        socket = WebSocket(request: request)
        socket.delegate = self
        socket.connect()
    }
    
    func didReceive(event: WebSocketEvent, client: WebSocket) {
            switch event {
            case .connected(let headers):
                isConnected = true
                print("🤡🤡 websocket is connected: \(headers)")
            case .disconnected(let reason, let code):
                isConnected = false
                print("🤡🤡 websocket is disconnected: \(reason) with code: \(code)")
            case .text(let string):
                print("🟡🟡🟡 Received text: \(string)")
                
                // if event
                delegate.didReceiveEvent(text: string)
            case .binary(let data):
                print("🟡🟡🟡 Received data: \(data.count)")
            case .ping(_):
                print("🤡 PING")
                break
            case .pong(_):
                print("🤡 PONG")
                break
            case .viabilityChanged(_):
                break
            case .reconnectSuggested(_):
                break
            case .cancelled:
                print("🤡 CANCELLED")
                isConnected = false
            case .error(let error):
                print("🤡🤡🤡🤡🤡 ERROR")
                isConnected = false
                handleError(error)
            }
        }
        
        func handleError(_ error: Error?) {
            if let e = error as? WSError {
                print("🟡 websocket encountered an error: \(e.message)")
            } else if let e = error {
                print("🟡 websocket encountered an error: \(e.localizedDescription)")
            } else {
                print("🟡 websocket encountered an error")
            }
        }
    
    func send(text:String) {
        socket.write(string:text)
    }
    
    func disconnect() {
        if isConnected {
            socket.disconnect()
        } else {
            socket.connect()
        }
    }
}

class ConnectionManager {
    
    static let shared = ConnectionManager()
    
    var relaySockets = [RelaySocket]()
    
    func sendMessage(_ message:ClientMessage) {
        for relaySocket in relaySockets {
            if relaySocket.isConnected {
//                print("🟢 sending message: \(text)")
//                relaySocket.send(text: text)
                if message.type == .REQ || message.type == .CLOSE { // REQ AND CLOSE IS FOR ALL RELAYS
                    print("🟢 requesting from \(relaySocket.relay.url!): \(message.message)")
                    relaySocket.send(text: message.message)
                }
                else if message.type == .EVENT && relaySocket.relay.write { // EVENT IS ONLY FOR WRITE RELAYS
                    print("🟢 publishing to \(relaySocket.relay.url!): \(message.message)")
                    relaySocket.send(text: message.message)
                }
            }
        }
    }
}

struct ClientMessage {
    enum type {
        case EVENT
        case REQ
        case CLOSE
    }
    
    var type:ClientMessage.type = .EVENT
    var message:String
    
    
}


struct RequestMessage {
    
    static func getAuthorNotes(pubkey:String, limit:Int = 100, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [1], "limit": \(limit)}]
"""
    }
    
    static func getAuthorsNotes(pubkeys:[String?], limit:Int = 100, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(JSON(pubkeys).rawString() ?? "[]")"], "kinds": [1], "limit": \(limit)}]
"""
    }

    static func getUserMetadata(pubkey:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [0], "limit": 1}]
"""
    }
    
    static func getUserMetadata(pubkeys:[String?], subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": \(JSON(pubkeys).rawString() ?? "[]"), "kinds": [0], "limit": 1}]
"""
    }
}

//struct NostrEvent {
//    var id: String
//    var kind: Int
//    var pubKey: String
//    var sig: String
//    var tagsSerialized: String
//    var createdAt: Int
//    var content: String
//}
