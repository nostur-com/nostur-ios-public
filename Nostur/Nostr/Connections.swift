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
//    func didReceiveEvent(text: String)
    func didReceiveMessage(text: String) async throws
}

class RelaySocket : WebSocketDelegate, ObservableObject {
    var delegate: EventDelegate?
    @Published var relay: Relay
    
    @Published var socket: WebSocket!
    
    var isConnected: Bool {
        get { relay.isConnected }
        set(value) { relay.isConnected = value }
    }
    
    init(relay: Relay, delegate: EventDelegate? = nil) {
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
            relay.isConnected = true
            print("🟢 websocket is connected: \(headers)")
        case .disconnected(let reason, let code):
            relay.isConnected = false
            print("🟠 websocket is disconnected: \(reason) with code: \(code)")
        case .text(let string):
            print("💬 Received text: \(string)".prefix(260))
            
            if (delegate != nil) {
                _ = Task {
                    try! await delegate!.didReceiveMessage(text: string)
                }
            }
        case .binary(let data):
            print("💾 Received data: \(data.count)")
        case .ping(_):
//            print("PING")
            break
        case .pong(_):
//            print("PONG")
            break
        case .viabilityChanged(_):
            break
        case .reconnectSuggested(_):
            break
        case .cancelled:
            print("🔴 CANCELLED \(relay.url ?? "(no url)")")
            relay.isConnected = false
        case .error(let error):
            print("🔴🔴🔴🔴 ERROR \(relay.url ?? "(no url)")")
            relay.isConnected = false
            handleError(error)
        }
    }
    
    func handleError(_ error: Error?) {
        if let e = error as? WSError {
            print("🔴🔴🔴🔴 Websocket encountered an error: \(e.message)")
        } else if let e = error {
            print("🔴🔴🔴🔴 webSocket encountered an error: \(e.localizedDescription)")
        } else {
            print("🔴🔴🔴🔴 websockeT encountered an error")
        }
    }
    
    func send(text:String) {
        socket.write(string:text)
    }
    
    func disconnect() {
        if relay.isConnected {
            socket.disconnect()
            relay.isConnected = false
        }
    }
}

class ConnectionManager: ObservableObject {
    
//    static let shared = ConnectionManager()
    
    @Published var relaySockets = [RelaySocket]()
    var eventReceivingDelegate:EventDelegate? = nil
    
    func sendMessage(_ message:ClientMessage) {
        for relaySocket in relaySockets {
            if relaySocket.isConnected {
                //                print("🟢 sending message: \(text)")
                //                relaySocket.send(text: text)
                if message.type == .REQ || message.type == .CLOSE { // REQ AND CLOSE IS FOR ALL RELAYS
//                    dump("🟢 SENDING TO \(relaySocket.relay.url!): \(message.message)")
//                    print("🟢 SENDING TO \(relaySocket.relay.url!): \(message.message)".prefix(260))
                    relaySocket.send(text: message.message)
                }
                else if message.type == .EVENT && relaySocket.relay.write { // EVENT IS ONLY FOR WRITE RELAYS
                    print("🟢 PUBLISHING TO \(relaySocket.relay.url!): \(message.message)")
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
    
    static func close(subscriptionId:String) -> String {
        return "[\"CLOSE\", \"\(subscriptionId)\"]"
    }
}

struct RelayMessage {
    
    enum type:String {
        case EVENT
        case NOTICE
        case EOSE
    }
    
    enum error:Error {
        case FAILED_TO_PARSE // Failed to parse raw websocket
        case UNKNOWN_MESSAGE_TYPE // NOT EVENT, NOTICE or EOSE
        case FAILED_TO_PARSE_EVENT // Could parse raw websocket but not event
    }
    
    var type:RelayMessage.type?
    var message:String
    var subscriptionId:String?
    var event:NEvent?
    
    static func parseRelayMessage(text:String, skipValidation:Bool = false) throws -> RelayMessage {
        guard let dataFromString = text.data(using: .utf8, allowLossyConversion: false) else {
            throw error.FAILED_TO_PARSE
        }
        
        guard let json = try? JSON(data: dataFromString) else {
            throw error.FAILED_TO_PARSE
        }
        
        guard json[0] != "EOSE" else {
            return RelayMessage(type: .EOSE, message: text, subscriptionId: json[1].stringValue)
        }
        
        guard json[0] != "NOTICE" else {
            return RelayMessage(type: .NOTICE, message: text)
        }
        
        guard json[0] == "EVENT" else {
            throw error.UNKNOWN_MESSAGE_TYPE
        }
        
        let decoder = JSONDecoder()
        guard let event = try? decoder.decode(NEvent.self, from: Data(json[2].rawData())) else {
            throw error.FAILED_TO_PARSE_EVENT
        }
        
        guard try skipValidation || event.verified() else {
            print("🟣\(event)")
            throw "🔴🔴🔴 NO VALID SIG 🔴🔴🔴 "
        }
        
        return RelayMessage(type: .EVENT, message: text, subscriptionId: json[1].stringValue, event: event)
    }
}

struct RequestMessage {
    
    // FETCH A SINGLE EVENT
    static func getEvent(id:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"ids":"[\(id)]"), "limit": 1}]
"""
    }
    
    static func getEvents(ids:[String?], limit:Int? = 500, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"ids": \(JSON(ids).rawString() ?? "[]"), "limit": \(limit)}]
"""
    }
    
    // For fetching events posted by people you follow
    // or reactions by others reacting to the people you follow
    static func getFollowingEvents(pubkeys:[String?], limit:Int = 500, subscriptionId:String? = nil, since:NTimestamp? = nil) -> String {
        
        if since != nil {
            return """
    ["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": \(JSON(pubkeys).rawString() ?? "[]"), "limit": \(limit), "since": \(since!.timestamp)}, {"#p": \(JSON(pubkeys).rawString() ?? "[]"), "limit": \(limit), "since": \(since!.timestamp)}]
    """
        }
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": \(JSON(pubkeys).rawString() ?? "[]"), "limit": \(limit)}]
"""
    }
    
    
    
    static func getAuthorContactsList(pubkey:String, limit:Int = 1, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [3], "limit": \(limit)}]
"""
    }
    
    static func getAuthorNotes(pubkey:String, limit:Int = 100, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [1], "limit": \(limit)}]
"""
    }
    
    static func getAuthorsEvents(pubkeys:[String?], limit:Int = 200, subscriptionId:String? = nil, since:NTimestamp? = nil) -> String {
        
        if since != nil {
            return """
    ["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": \(JSON(pubkeys).rawString() ?? "[]"), "limit": \(limit), "since": \(since!.timestamp)}]
    """
        }
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": \(JSON(pubkeys).rawString() ?? "[]"), "limit": \(limit)}]
"""
    }
    
    static func getAuthorsNotes(pubkeys:[String?], limit:Int = 100, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": \(JSON(pubkeys).rawString() ?? "[]"), "kinds": [1], "limit": \(limit)}]
"""
    }
    
    static func getUserMetadata(pubkey:String, subscriptionId:String? = nil) -> String {
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": ["\(pubkey)"], "kinds": [0], "limit": 1}]
"""
    }
    
    static func getUserMetadata(pubkeys:[String?], limit:Int? = nil, subscriptionId:String? = nil) -> String {
        let limit = limit ?? (pubkeys.count + 20) // add 20 in case of multiple setMetadata's for a pubkey maybe?? not sure
        return """
["REQ", "\(subscriptionId ?? UUID().uuidString)", {"authors": \(JSON(pubkeys).rawString() ?? "[]"), "kinds": [0], "limit": \(limit)}]
"""
    }
}
