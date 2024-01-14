//
//  NetworkMonitor.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/11/2023.
//

import Foundation
import Network
import Combine

public class NetworkMonitor: ObservableObject {
    
    static public let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private var queue = DispatchQueue(label: "network-monitor")
    
    @Published public var isConnected: Bool = true
    
    // Helper for SwiftUI views where a negative binding is needed
    // (example: .fullScreenCover(isPresented: $networkMonitor.isDisconnected)
    // !$networkMonitor.isConnected is not possible but $networkMonitor.isDisconnected works.
    public var isDisconnected: Bool {
        get { !isConnected }
        set { isConnected = !newValue }
    }
    
    private var subscriptions = Set<AnyCancellable>()
    public var isConnectedSubject = PassthroughSubject<Bool, Never>()
    
    init() {
        isConnectedSubject
            .subscribe(on: queue)
            .receive(on: RunLoop.main)
            .sink { [weak self] isConnected in
                self?.isConnected = isConnected
            }
            .store(in: &subscriptions)
        
        monitor.pathUpdateHandler = { path in
            self.isConnectedSubject.send(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }
}
