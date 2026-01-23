//
//  SpamFilteringSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2026.
//

import SwiftUI
import NavigationBackport

struct ZapsSettings: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var la: LoggedInAccount
    @ObservedObject private var settings: SettingsStore = .shared
    
    @State private var albyNWCsheetShown = false
    @State private var customNWCsheetShown = false
    @State private var showDefaultZapAmountSheet = false
    
    var body: some View {
        NXForm {
            Section(header: Text("Zapping", comment:"Setting heading on settings screen")) {
                
                LightningWalletPicker()
                
                HStack {
                    Text("Default zap amount:")
                    Spacer()
                    Text("\(SettingsStore.shared.defaultZapAmount.clean) sats \(Image(systemName: "chevron.right"))")
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    showDefaultZapAmountSheet = true
                }
                .onChange(of: settings.defaultLightningWallet) { newWallet in
                    if newWallet.scheme == "nostur:nwc:alby:" {
                        // trigger alby setup
                        albyNWCsheetShown = true
                    }
                    else if newWallet.scheme == "nostur:nwc:custom:" {
                        // trigger custom NWC setup
                        customNWCsheetShown = true
                    }
                    else if newWallet.scheme.starts(with: "nostur:nwc:last:") {

                    }
                    else {
                        settings.activeNWCconnectionId = ""
                    }
                }
                
                
                if settings.nwcReady {
                    Toggle(isOn: $settings.nwcShowBalance) {
                        Text("Show wallet balance", comment:"Setting on settings screen")
                        Text("Will show balance in side bar", comment:"Setting on settings screen")
                    }
                    .onChange(of: settings.nwcShowBalance) { enabled in
                        if enabled {
                            nwcSendBalanceRequest()
                        }
                    }
                    
                    Picker(selection: $settings.thunderzapLevel) {
                        ForEach(ThunderzapLevel.allCases, id:\.self) {
                            Text($0.localized).tag($0.rawValue)
                                .foregroundColor(theme.primary)
                        }
                    } label: {
                        Text("Lightning sound effect", comment:"Setting on settings screen")
                    }
                    .pickerStyleCompatNavigationLink()
                }
            }
            
            Section(header: Text("Appearance", comment: "Setting heading on settings screen")) {
                Toggle(isOn: $settings.showFiat) {
                    VStack(alignment: .leading) {
                        Text("Show fiat value", comment: "Setting on settings screen")
                        Text("Show USD value next to sats on posts", comment:"Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showDefaultZapAmountSheet) {
            NBNavigationStack {
                SettingsDefaultZapAmount()
                    .environment(\.theme, theme)
                    .presentationBackgroundCompat(theme.listBackground)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
        .sheet(isPresented: $albyNWCsheetShown) {
            NRNavigationStack {
                AlbyNWCConnectSheet()
            }
            .environmentObject(la)
            .presentationBackgroundCompat(theme.listBackground)
        }
        .sheet(isPresented: $customNWCsheetShown) {
            NRNavigationStack {
                CustomNWCConnectSheet()
            }
            .environmentObject(la)
            .presentationBackgroundCompat(theme.listBackground)
        }
    }
}

#Preview {
    ZapsSettings()
}
