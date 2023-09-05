//
//  DMSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/09/2023.
//

import SwiftUI

struct DMSettings: View {
    @Binding var showDMToggles:Bool
    
    var body: some View {
        Rectangle().fill(.thinMaterial)
            .ignoresSafeArea()
            .onTapGesture {
                showDMToggles = false
            }
            .overlay(alignment: .top) {
                Box {
                    VStack(alignment: .leading) {
                        if (DirectMessageViewModel.default.unread + DirectMessageViewModel.default.newRequests) > 0 {
                            Button("Mark all as read") {
                                DirectMessageViewModel.default.markAcceptedAsRead()
                                DirectMessageViewModel.default.markRequestsAsRead()
                                showDMToggles = false
                            }
                            .hCentered()
                            
                            Divider()
                        }
                        
                        HStack {
                            Text("Missing mesages?")
                            Button("Rescan") {
                                DirectMessageViewModel.default.rescanForMissingDMs(12)
                                showDMToggles = false
                            }
                        }
                        .hCentered()
                    }
                }
                .padding(20)
                .ignoresSafeArea()
                .offset(y: 1.0)
            }
            .onReceive(receiveNotification(.showDMToggles)) { _ in
                if showDMToggles {
                    showDMToggles = false
                }
            }
    }
}

struct DMSettings_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            DMSettings(showDMToggles: .constant(true))
        }
    }
}

