//
//  Settings.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/02/2023.
//

import SwiftUI

struct Settings: View {
    @EnvironmentObject var ns: NosturState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var er: ExchangeRateModel
    
//    @State var showDocPicker = false
    @State var showExporter = false
    
    var fiatPrice:String {
        String(format: "$%.02f", (ceil(Double(settings.defaultZapAmount)) / 100000000 * er.bitcoinPrice))
    }
    
    var amountS:Float {
        mapLinearToExponential(value: Float(sliderValue), min: Float(SLIDER_MIN), max: Float(SLIDER_MAX), exponent: 7)
    }
    let SLIDER_MIN = 500.0
    let SLIDER_MAX = 2000000.0
    
    @State var sliderValue = 0.0

    var body: some View {
        VStack {
            Form {
                Section(header: Text("Message verification")) {
                    Toggle(isOn: $settings.isSignatureVerificationEnabled) {
                        Text("Verify message signatures")
                        Text("Turn off to save battery life and trust the relays for the authenticity of messages")
                    }
                }
                
                Section(header: Text("Display")) {
                    Toggle(isOn: $settings.hideBadges) {
                        Text("We Don't Need No Stinkin' Badges")
                        Text("Hides badges from profiles and feeds")
                    }
                    Toggle(isOn: $settings.hideEmojisInNames) {
                        Text("Hide emojis in names")
                    }
                    Toggle(isOn: $settings.restrictAutoDownload) {
                        Text("Restrict images to following")
                        Text("Only auto-download images in new posts from people you follow\nToggle off to download from all")
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
                        
                        Slider(value: $sliderValue, in: SLIDER_MIN...SLIDER_MAX) {
                            
                        } minimumValueLabel: {
                            Text("\(SLIDER_MIN.clean)")
                        } maximumValueLabel: {
                            Text("\(SLIDER_MAX.clean)")
                        }
                        Text("Zap \(settings.defaultZapAmount.satsFormatted) sats by default (\(fiatPrice))")
                    }
                }
                
                Section(header:Text("Data export")) {
                    Button("Save to file...") {
                        guard ns.account != nil else { print("cannot export, no account"); return }
                        showExporter.toggle()
                    }
                    if (showExporter) {
                        Color.clear
                            .fileExporter(isPresented: $showExporter, document: EventsArchive(pubkey: ns.account!.publicKey), contentType: .events, defaultFilename: "Exported Nostur Events - \(String(ns.account!.npub.prefix(11)))") { result in
                                switch result {
                                    case .success(let url):
                                        print("Saved to \(url)")
                                    case .failure(let error):
                                        print(error.localizedDescription)
                                }
                            }
                    }
                }
                
//                Section(header: Text("Private key protector")) {
//                    Toggle(isOn: $settings.replaceNsecWithHunter2Enabled) {
//                        Text("Don't allow nsec in posts")
//                        Text("Replaces any \"nsec1...\" in new posts with \"hunter2\" ")
//                    }
//                }
            }
            
//            if (ns.account != nil) {
//                ShareLink(item: ns.account!.publicKey, preview: SharePreview("All things you published with Nostur")) {
//                    Text("Export your data")
//                }
//            }
//            Button("Export your posts") {
//                guard let account = ns.account else { print("cannot export, no account"); return }
//                showDocPicker.toggle()
//            }
//            .sheet(isPresented: $showDocPicker, content: {
//
//
//                    .presentationDetents([.medium])
//            })
        }
        .onAppear {
            sliderValue = settings.defaultZapAmount
        }
        .onChange(of: amountS, perform: { newValue in
            settings.defaultZapAmount = Double(newValue)
        })
            .navigationTitle("Settings")
//            .navigationBarHidden(true)
    }
}

struct Settings_Previews: PreviewProvider {
    static var previews: some View {
        Settings()
            .withPreviewEnvironment()
    }
}
