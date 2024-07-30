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
    
    public var vpnDetected: Bool {
        vpnConfigurationDetected && actualVPNconnectionDetected
    }
    
    @Published public var vpnConfigurationDetected: Bool = false
    @Published public var actualVPNconnectionDetected: Bool = false
    
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
                    
                    if isConnected {
                        self.detectActualConnection()
                    }
                    else {
                        DispatchQueue.main.async {
                            self.vpnConfigurationDetected = false
                            self.actualVPNconnectionDetected = false
                            if SettingsStore.shared.enableVPNdetection {
                                ConnectionPool.shared.disconnectAllAdditional()
                            }
                        }
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
        self.detectActualConnection()
    }
    
    
    // https://stackoverflow.com/a/72295973/9889453
    private func detectActualConnection() {
        guard SettingsStore.shared.enableVPNdetection else { return }
        
        // Check if connection to host is being routed over transparent proxy (such as VPN)
        let c = NWConnection(host: "protection.nostur.com", port: 443, using: .tcp)
        c.stateUpdateHandler = { state in
            if (state == .ready) {
                if (c.currentPath?.usesInterfaceType(.other) == true) {
                    DispatchQueue.main.async {
                        self.actualVPNconnectionDetected = true
                    }
                    L.sockets.debug("📡📡 Connection is over VPN")
                } else {
                    DispatchQueue.main.async {
                        self.actualVPNconnectionDetected = false
                    }
                    L.sockets.debug("📡📡 Connection is not over VPN")
                }
                c.cancel()
            }
        }
        c.start(queue: .main)
    }
    
}
