//
//  RelaysAndConnectionsSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2026.
//

import SwiftUI

struct RelaysAndConnectionsSettings: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared
    @ObservedObject private var network: NetworkMonitor = .shared
    
    var body: some View {
        NXForm {
            Section(header: Text("Relays", comment: "Relay settings heading")) {
                RelaysLink()
                    .listRowBackground(theme.background)
                
                RelayMasteryLink() // Wrapped in View else SwiftUI will freeze
                    .listRowBackground(theme.background)
                
                Toggle(isOn: $settings.enableOutboxRelays) {
                    VStack(alignment: .leading) {
                        Text("Autopilot", comment: "Setting on settings screen")
                        Text("Automatically connect to additional relays from people you follow to reduce missing content that can't be found on your own relay set", comment: "Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: settings.enableOutboxRelays) { newValue in
                    guard newValue == true, let loggedInAccount = AccountsState.shared.loggedInAccount, loggedInAccount.outboxLoader == nil else { return }
                    loggedInAccount.outboxLoader = OutboxLoader(pubkey: loggedInAccount.pubkey, follows: loggedInAccount.viewFollowingPublicKeys, cp: ConnectionPool.shared)
                }
      
                
                Toggle(isOn: $settings.followRelayHints) {
                    VStack(alignment: .leading) {
                        Text("Follow relay hints", comment: "Setting on settings screen")
                        Text("Connect to relays included in nostr links when content can't be found", comment:"Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                if settings.enableOutboxRelays || settings.followRelayHints {
                    Toggle(isOn: $settings.enableVPNdetection) {
                        VStack(alignment: .leading) {
                            Text("VPN detection", comment: "Setting on settings screen")
                            Text("Only connect to additional relays when a VPN is active")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            
                            if network.vpnDetected {
                                HStack(spacing: 3) {
                                    Image(systemName: "circle.fill").foregroundColor(.green)
                                    Text("VPN detected")
                                        .foregroundColor(.secondary)
                                }
                                .font(.footnote)
                            }
                            else {
                                HStack(spacing: 3) {
                                    Image(systemName: "circle.fill").foregroundColor(.red)
                                    Text("VPN not detected")
                                        .foregroundColor(.secondary)
                                }
                                .font(.footnote)
                            }
                        }
                    }
                    .onChange(of: settings.enableVPNdetection) { newValue in
                        if newValue {
                            NetworkMonitor.shared.detectActualConnection()
                        }
                    }
                }
                
                RelaysStatsLink()
                    .listRowBackground(theme.background)
                
            }
        }
    }
}

#Preview {
    RelaysAndConnectionsSettings()
}
