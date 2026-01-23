//
//  AppearanceSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2026.
//

import SwiftUI

struct AppearanceSettings: View {
    @ObservedObject private var settings: SettingsStore = .shared
    
    var body: some View {
        NXForm {
            Section(header: Text("Appearance", comment:"Setting heading on settings screen")) {
                Group {
                    if IS_CATALYST {
                        Toggle(isOn: $settings.proMode) {
                            VStack(alignment: .leading) {
                                Text("Nostur Pro", comment:"Setting on settings screen")
                                Text("Multi-columns and more")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if #available(iOS 16, *) {
                        ThemePicker()
                    }

                    if !AVAILABLE_26 { // Starting 26.0, full width is always on
                        Toggle(isOn: $settings.fullWidthImages) {
                            Text("Enable full width pictures", comment:"Setting on settings screen")
                        }
                    }
                    
                    Toggle(isOn: $settings.enableLiveEvents) {
                        Text("Show Live banner", comment:"Setting on settings screen")
                        Text("Live Nests or streams from follows")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    
                    Toggle(isOn: $settings.animatedPFPenabled) {
                        VStack(alignment: .leading) {
                            Text("Enable animated profile pics", comment:"Setting on settings screen")
                            Text("Disable to improve scrolling performance", comment:"Setting on settings screen")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    Toggle(isOn: $settings.rowFooterEnabled) {
                        VStack(alignment: .leading) {
                            Text("Show post stats on timeline", comment:"Setting on settings screen")
                            Text("Counters for replies, likes, zaps etc.", comment:"Setting on settings screen")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Toggle(isOn: $settings.displayUserAgentEnabled) {
                        VStack(alignment: .leading) {
                            Text("Show from which app someone posted", comment:"Setting on settings screen")
                            Text("Will show from which app/client something was posted, if available", comment:"Setting on settings screen")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                                        
                    FooterConfiguratorLink() // Put NavigationLink in own view or freeze.
                    
                    if settings.footerButtons.contains("⚡️") || settings.footerButtons.contains("⚡") {
                        Toggle(isOn: $settings.showFiat) {
                            VStack(alignment: .leading) {
                                Text("Show zaps fiat value", comment: "Setting on settings screen")
                                Text("Show USD value next to sats on post", comment:"Setting on settings screen")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                Toggle(isOn: $settings.fetchCounts) {
                    VStack(alignment: .leading) {
                        Text("Fetch counts on timeline", comment:"Setting on settings screen")
                        Text("Fetches like/zaps/replies counts as posts appear", comment:"Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                Toggle(isOn: $settings.autoScroll) {
                    VStack(alignment: .leading) {
                        Text("Auto scroll to new posts", comment:"Setting on settings screen")
                        Text("When at top, auto scroll if there are new posts", comment:"Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                Toggle(isOn: $settings.appWideSeenTracker) {
                    VStack(alignment: .leading) {
                        Text("Hide posts you have already seen (beta)", comment:"Setting on settings screen")
                        Text("Keeps track across all feeds posts you have already seen, don't show them again", comment:"Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                if settings.appWideSeenTracker && FileManager.default.ubiquityIdentityToken != nil {
                    Toggle(isOn: $settings.appWideSeenTrackeriCloud) {
                        VStack(alignment: .leading) {
                            Text("Hide posts you have already seen on multiple devices", comment:"Setting on settings screen")
                            Text("Uses iCloud to sync across devices", comment:"Setting on settings screen")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Toggle(isOn: $settings.statusBubble) {
                    VStack(alignment: .leading) {
                        Text("Loading indicator", comment:"Setting on settings screen")
                        Text("Shows when items are being processed", comment:"Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                Toggle(isOn: $settings.hideBadges) {
                    VStack(alignment: .leading) {
                        Text("We Don't Need No Stinkin' Badges", comment:"Setting on settings screen")
                        Text("Hides badges from profiles and feeds", comment: "Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: $settings.includeSharedFrom) {
                    VStack(alignment: .leading) {
                        Text("Include Nostur caption when sharing posts", comment:"Setting on settings screen")
                        Text("Shows 'Shared from Nostur' caption when sharing post screenshots", comment: "Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                
                Toggle(isOn: $settings.enableOutboxPreview) {
                    VStack(alignment: .leading) {
                        Text("Show extra relays used on post preview", comment: "Setting on settings screen")
                        Text("If Relay Autopilot is enabled show which additional relays will be used", comment: "Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    AppearanceSettings()
}
