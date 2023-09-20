//
//  Hot+FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/09/2023.
//

import SwiftUI

struct HotFeedSettings: View {
    
    @ObservedObject var hotVM:HotViewModel
    @Binding var showFeedSettings:Bool
    @State var needsReload = false
    
    var body: some View {
        Rectangle().fill(.thinMaterial)
            .ignoresSafeArea()
            .onTapGesture {
                showFeedSettings = false
            }
            .overlay(alignment: .top) {
                Box {
                    VStack(alignment: .leading) {
                        AppThemeSwitcher(showFeedSettings: $showFeedSettings)
                            .padding(.bottom, 15)
                        Text("Settings for: Hot")
                            .fontWeight(.bold)
                            .hCentered()
                            .padding(.bottom, 20)
                        
                        Text("Time frame")
                            .frame(maxWidth: .infinity, alignment: .center)
                        Picker("Time frame", selection: $hotVM.ago) {
                            Text("48h").tag(48)
                            Text("24h").tag(24)
                            Text("12h").tag(12)
                            Text("8h").tag(8)
                            Text("4h").tag(4)
                            Text("2h").tag(2)
                        }
                        .pickerStyle(.segmented)
                        
                        Text("The Hot feed shows posts most liked by people you follow in the last \(hotVM.ago) hours")
                            .padding(.top, 20)
                    }
                }
                .padding(20)
                .ignoresSafeArea()
                .offset(y: 1.0)
            }
            .onReceive(receiveNotification(.showFeedToggles)) { _ in
                if showFeedSettings {
                    showFeedSettings = false
                }
            }
    }
}

struct HotFeedSettingsTester: View {

    var body: some View {
        NavigationStack {
            VStack {
                HotFeedSettings(hotVM: HotViewModel(), showFeedSettings: .constant(true))
                Spacer()
            }
        }
        .onAppear {
            Theme.default.loadPurple()
        }
    }
}


struct HotFeedSettings_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            HotFeedSettingsTester()
        }
    }
}

