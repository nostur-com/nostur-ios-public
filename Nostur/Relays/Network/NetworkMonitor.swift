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
                            if !self.vpnConfigurationDetected {
                                self.vpnConfigurationDetected = false
                            }
                            if !self.actualVPNconnectionDetected {
                                self.actualVPNconnectionDetected = false
                            }
                            if SettingsStore.shared.enableVPNdetection {
                                ConnectionPool.shared.disconnectAllAdditional()
                            }
                        }
                    }
                }
            }
            .store(in: &subscriptions)
        
        // Detect actual VPN connection again after first relay connection
        receiveNotification(.firstConnection)
            .debounce(for: .seconds(0.1), scheduler: DispatchQueue.global())
            .sink { [weak self] _ in
                self?.detectActualConnection()
            }
            .store(in: &subscriptions)
        
        
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnectedSubject.send(path.status == .satisfied)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let usesOtherInterface = path.usesInterfaceType(.other)
                if self.vpnConfigurationDetected != usesOtherInterface {
                    self.vpnConfigurationDetected = usesOtherInterface
                }
            }
        }
        monitor.start(queue: queue)
        self.detectActualConnection()
    }
    
    
    // https://stackoverflow.com/a/72295973/9889453
    public func detectActualConnection() {
        guard SettingsStore.shared.enableVPNdetection else { return }
        
        // Check if connection to host is being routed over transparent proxy (such as VPN)
        let c = NWConnection(host: "protection.nostur.com", port: 443, using: .tcp)
        c.stateUpdateHandler = { [weak self] state in
            if (state == .ready) {
                if (c.currentPath?.usesInterfaceType(.other) == true) {
                    DispatchQueue.main.async { [weak self] in
                        self?.actualVPNconnectionDetected = true
                    }
#if DEBUG
                    L.sockets.debug("📡📡 Connection is over VPN")
#endif
                } else {
                    DispatchQueue.main.async {
                        self?.actualVPNconnectionDetected = false
                    }
#if DEBUG
                    L.sockets.debug("📡📡 Connection is not over VPN")
#endif
                }
                c.cancel()
            }
        }
        c.start(queue: .main)
    }
    
}
