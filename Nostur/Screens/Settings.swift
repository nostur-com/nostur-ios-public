//
//  Settings.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/02/2023.
//

import SwiftUI

struct Settings: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var er: ExchangeRateModel
    
    var fiatPrice:String {
        String(format: "$%.02f", (ceil(Double(settings.defaultZapAmount)) / 100000000 * er.bitcoinPrice))
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Message verification")) {
                    Toggle(isOn: $settings.isSignatureVerificationEnabled) {
                        Text("Verify message signatures")
                        Text("Turn off to save battery life and trust the relays for the authenticity of messages")
                    }
                }
                
                Section(header: Text("Zapping")) {
                    
                    VStack {
                        Picker(selection: $settings.defaultLightningWallet) {
                            ForEach(SettingsStore.walletOptions) {
                                Text($0.name).tag($0)
                            }
                        } label: {
                            Text("Lightning wallet")
                        }
                        
                        Slider(value: $settings.defaultZapAmount, in: 1000...200000) {
                            
                        } minimumValueLabel: {
                            Text("0")
                        } maximumValueLabel: {
                            Text("200000")
                        }
                        Text("Zap \(settings.defaultZapAmount.satsFormatted) sats by default (\(fiatPrice))")
                    }
                }
                
//                Section(header: Text("Private key protector")) {
//                    Toggle(isOn: $settings.replaceNsecWithHunter2Enabled) {
//                        Text("Don't allow nsec in posts")
//                        Text("Replaces any \"nsec1...\" in new posts with \"hunter2\" ")
//                    }
//                }
            }
//            .navigationBarTitle(Text("Settings"))
        }
    }
}

struct Settings_Previews: PreviewProvider {
    static var previews: some View {
        Settings()
            .withPreviewEnvironment()
    }
}
