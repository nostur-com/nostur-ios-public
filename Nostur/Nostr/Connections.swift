////
////  Connections.swift
////  Nostur
////
////  Created by Fabian Lachman on 09/01/2023.
////
//
////import SwiftUI
//import Foundation
////import Starscream
////import NostrKit
//import SwiftyJSON
//import Combine
//
//protocol WebSocketConnection {
//    func send(text: String)
//    func send(data: Data)
//    func connect()
//    func disconnect()
//    var delegate: WebSocketConnectionDelegate? {
//        get
//        set
//    }
//}
//
//protocol WebSocketConnectionDelegate {
//    func onConnected(connection: WebSocketConnection)
//    func onDisconnected(connection: WebSocketConnection, error: Error?)
//    func onError(connection: WebSocketConnection, error: Error)
//    func onMessage(connection: WebSocketConnection, text: String)
//    func onMessage(connection: WebSocketConnection, data: Data)
//}
//
//class WebSocketTaskConnection: NSObject, WebSocketConnection, URLSessionWebSocketDelegate {
//    var delegate: WebSocketConnectionDelegate?
//    var webSocketTask: URLSessionWebSocketTask!
//    var urlSession: URLSession!
//    let delegateQueue = OperationQueue()
//    
//    init(url: URL) {
//        super.init()
//        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
//        webSocketTask = urlSession.webSocketTask(with: url)
//    }
//    
//    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
//        self.delegate?.onConnected(connection: self)
//    }
//    
//    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
//        self.delegate?.onDisconnected(connection: self, error: nil)
//    }
//    
//    func connect() {
//        webSocketTask.resume()
//        
//        listen()
//    }
//    
//    func disconnect() {
//        webSocketTask.cancel(with: .goingAway, reason: nil)
//    }
//    
//    func listen()  {
//        webSocketTask.receive { result in
//            switch result {
//            case .failure(let error):
//                self.delegate?.onError(connection: self, error: error)
//            case .success(let message):
//                switch message {
//                case .string(let text):
//                    self.delegate?.onMessage(connection: self, text: text)
//                case .data(let data):
//                    self.delegate?.onMessage(connection: self, data: data)
//                @unknown default:
//                    fatalError()
//                }
//                
//                self.listen()
//            }
//        }
//    }
//    
//    func send(text: String) {
//        webSocketTask.send(URLSessionWebSocketTask.Message.string(text)) { error in
//            if let error = error {
//                self.delegate?.onError(connection: self, error: error)
//            }
//        }
//    }
//    
//    func send(data: Data) {
//        webSocketTask.send(URLSessionWebSocketTask.Message.data(data)) { error in
//            if let error = error {
//                self.delegate?.onError(connection: self, error: error)
//            }
//        }
//    }
//}
//
//
//
//public protocol EventDelegate {
////    func didReceiveEvent(text: String)
//    func didReceiveMessage(text: String) throws
//}
//
//class RelaySocket: ObservableObject, WebSocketConnectionDelegate {
//    func onConnected(connection: WebSocketConnection) {
//        relay.isConnected = true
//    }
//    
//    func onDisconnected(connection: WebSocketConnection, error: Error?) {
//        relay.isConnected = false
//    }
//    
//    func onError(connection: WebSocketConnection, error: Error) {
//        print("onError 😛😛😛")
//        print(error)
//    }
//    
//    func onMessage(connection: WebSocketConnection, text: String) {
//        do {
//            try delegate?.didReceiveMessage(text: text)
//        }
//        catch {
//            print("onMessage error 😛😛😛")
//            print(error)
//        }
//    }
//    
//    func onMessage(connection: WebSocketConnection, data: Data) {
//        return
//    }
//    
//    var delegate: EventDelegate?
//    @Published var relay: Relay
////    @Published var socket: WebSocket!
//    var socket:WebSocketConnection
//    
////    var request:URLRequest
//    
//    var isConnected: Bool {
//        get { relay.isConnected }
//        set(value) { relay.isConnected = value }
//    }
//    
//    init(relay: Relay, delegate: EventDelegate? = nil) {
//        self.relay = relay
//        self.delegate = delegate
//        self.socket = WebSocketTaskConnection(url: URL(string: relay.url!)!)
//        self.socket.delegate = self
//    }
//    
//    
//    
//    
//    func connect() {
//        socket.connect()
//    }
//    
//    func send(text:String) {
//        socket.send(text: text)
//    }
//    
//    func disconnect() {
//        socket.disconnect()
//    }
//}
//
//
//
////class ConnectionManager: ObservableObject {
////    
////    static let shared = ConnectionManager()
////    
////    @Published var relaySockets = [RelaySocket]()
//////    var eventReceivingDelegate:EventDelegate? = nil
////    
////    func sendMessage(_ message:ClientMessage) {
////        print("🟢sendMessage: \(message.message.prefix(260))")
////        for relaySocket in relaySockets {
////            if relaySocket.isConnected {
////                //                print("🟢 sending message: \(text)")
////                //                relaySocket.send(text: text)
////                if message.type == .REQ || message.type == .CLOSE { // REQ AND CLOSE IS FOR ALL RELAYS
//////                    dump("🟢 SENDING TO \(relaySocket.relay.url!): \(message.message)")
//////                    print("🟢 SENDING TO \(relaySocket.relay.url!): \(message.message)".prefix(260))
////                    Task {
////                        await relaySocket.send(text: message.message)
////                    }
////                }
////                else if message.type == .EVENT && relaySocket.relay.write { // EVENT IS ONLY FOR WRITE RELAYS
////                    print("🟢 PUBLISHING TO \(relaySocket.relay.url!): \(message.message)")
////                    Task {
////                        await relaySocket.send(text: message.message)
////                    }
////                }
////            }
////        }
////    }
////}
//
