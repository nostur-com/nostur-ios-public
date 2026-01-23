//
//  Settings.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/02/2023.
//

import SwiftUI
import Combine
import CoreData
import Nuke
import NavigationBackport

struct Settings: View {
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared
    
    private var fiatPrice:String {
        String(format: "$%.02f", (ceil(Double(settings.defaultZapAmount)) / 100000000 * ExchangeRateModel.shared.bitcoinPrice))
    }
    
    @State var deleteAccountIsShown = false
    

    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        NXForm {
            
            NavigationLink {
                AppearanceSettings()
            } label: {
                Label("Appearance", systemImage: "switch.2")
            }
            
  
            Section {
                NavigationLink {
                    PostingAndUploadingSettings()
                } label: {
                    Label("Posting & Media Uploading", systemImage: "icloud.and.arrow.up")
                }
                
                NavigationLink {
                    ZapsSettings()
                } label: {
                    Label("Zaps", systemImage: "bolt")
                }
            }
            
            Section {
                NavigationLink {
                    RelaysAndConnectionsSettings()
                } label: {
                    Label("Relay Connections", systemImage: "point.3.filled.connected.trianglepath.dotted")
                }
                
                NavigationLink {
                    SpamFilteringSettings()
                } label: {
                    Label("Spam Filtering", systemImage: "checkmark.shield")
                }
            }
                  
            Section(header: Text("Data Usage", comment: "Setting heading on settings screen")) {
                Toggle(isOn: $settings.lowDataMode) {
                    VStack(alignment: .leading) {
                        Text("Low Data Mode", comment: "Setting on settings screen")
                        Text("Will not download media and previews", comment:"Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            NavigationLink {
                DatabaseAndCacheSettings()
            } label: {
                Label("Database & Cache", systemImage: "cylinder.split.1x2")
            }
            
       
            

            
            
            
            if account()?.privateKey != nil && !(account()?.isNC ?? false) {
                Section(header: Text("Account", comment: "Heading for section to delete account")) {
                    Button(role: .destructive) {
                        deleteAccountIsShown = true
                    } label: {
                        Label(String(localized:"Delete account", comment: "Button to delete account"), systemImage: "trash")
                    }                    
                }
                .listRowBackground(theme.background)
            }
        }
        .nosturNavBgCompat(theme: theme)
        .navigationTitle("Settings")
        .sheet(isPresented: $deleteAccountIsShown) {
            NRNavigationStack {
                DeleteAccountSheet()
            }
            .environmentObject(la)
            .presentationBackgroundCompat(theme.listBackground)
        }

    }
}

struct Settings_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadAccounts()
        }) {
            NBNavigationStack {
                Settings()
            }
        }
    }
}


protocol Localizable: RawRepresentable where RawValue: StringProtocol {}

extension Localizable {
    var localized: String {
        NSLocalizedString(String(rawValue), comment: "")
    }
}

struct FooterConfiguratorLink: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared
    
    var body: some View {
        NavigationLink(destination: {
            FooterConfigurator(footerButtons: $settings.footerButtons)
                .background(theme.listBackground)
        }, label: {
            HStack {
                Text("Reaction buttons")
                Spacer()
                Text(settings.footerButtons)
            }
        })
    }
}

struct RelayMasteryLink: View {
    @Environment(\.theme) private var theme
    @State private var relays: [CloudRelay] = []
    
    var body: some View {
        NavigationLink(destination: {
            RelayMastery(relays: relays)
                .presentationBackgroundCompat(theme.listBackground)
                .onAppear {
                    relays = CloudRelay.fetchAll()
                }
        }, label: {
            VStack(alignment: .leading) {
                Text("Announce your relays...")
                Text("Relays others will use to find your content")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        })
    }
}


struct RelaysLink: View {
    @Environment(\.theme) private var theme
    
    var body: some View {
        NavigationLink(destination: {
            RelaysView()
                .presentationBackgroundCompat(theme.listBackground)
        }, label: {
            VStack(alignment: .leading) {
                Text("Configure your relays...")
                Text("Relays Nostur uses to find or publish content")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        })
    }
}

struct RelaysStatsLink: View {
    @Environment(\.theme) private var theme
    var body: some View {
        NavigationLink(destination: {
            RelayStatsView(stats: ConnectionPool.shared.connectionStats)
                .presentationBackgroundCompat(theme.listBackground)
        }, label: {
            VStack(alignment: .leading) {
                Text("Relay connection stats")
            }
        })
    }
}
