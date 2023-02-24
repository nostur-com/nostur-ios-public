//
//  Settings.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/02/2023.
//

import SwiftUI

struct Settings: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Message verification")) {
                    Toggle(isOn: $settings.isSignatureVerificationEnabled) {
                        Text("Verify message signatures")
                        Text("Turn off to save battery life, but trust the relays for the authenticity of messages")
                    }
                }
                
                
                if (1 == 2) {
                    Section(header: Text("Sleep tracking settings")) {
                        Toggle(isOn: $settings.isSleepTrackingEnabled) {
                            Text("Sleep tracking:")
                        }
                        
                        Picker(
                            selection: $settings.sleepTrackingMode,
                            label: Text("Sleep tracking mode")
                        ) {
                            ForEach(SettingsStore.SleepTrackingMode.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        
                        Stepper(value: $settings.sleepGoal, in: 6...12) {
                            Text("Sleep goal is \(settings.sleepGoal) hours")
                        }
                    }
                    
                    if !settings.isPro {
                        Section {
                            Button(action: {
                                self.settings.unlockPro()
                            }) {
                                Text("Unlock PRO")
                            }
                            
                            Button(action: {
                                self.settings.restorePurchase()
                            }) {
                                Text("Restore purchase")
                            }
                        }
                    }
                }
            }
                .navigationBarTitle(Text("Settings"))
        }
    }
}

struct Settings_Previews: PreviewProvider {
    static var previews: some View {
        Settings()
            .withPreviewEnvironment()
    }
}
