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
    
    
    @Published public var vpnConfigurationDetected: Bool = false
    // Helper for SwiftUI views where a negative binding is needed
    // (example: .fullScreenCover(isPresented: $networkMonitor.isDisconnected)
    // !$networkMonitor.isConnected is not possible but $networkMonitor.isDisconnected works.
    public var isDisconnected: Bool {
        get { !isConnected }
        set { isConnected = !newValue }
    }
    
    private var subscriptions = Set<AnyCancellable>()
    public var isConnectedSubject = PassthroughSubject<Bool, Never>()
    
    private init() {
        isConnectedSubject
            .subscribe(on: queue)
            .receive(on: RunLoop.main)
            .sink { [weak self] isConnected in
                guard let self else { return }
                if self.isConnected != isConnected {
                    self.isConnected = isConnected
                }
                if isConnected {
                }
                else {
                    DispatchQueue.main.async {
                        self.vpnConfigurationDetected = false
                    }
                }
            }
            .store(in: &subscriptions)
        
        monitor.pathUpdateHandler = { path in
            self.isConnectedSubject.send(path.status == .satisfied)
            DispatchQueue.main.async {
                self.vpnConfigurationDetected = path.usesInterfaceType(.other)
            }
        }
        monitor.start(queue: queue)
    }
}
