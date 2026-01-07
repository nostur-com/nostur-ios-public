//
//  DMSettingsSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/01/2026.
//

import SwiftUI

struct DMSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: DMsVM
    
    var body: some View {
        NXForm {
            if (vm.unread + vm.unreadNewRequestsCount) > 0 {
                Button("Mark all as read") {
                    vm.markAcceptedAsRead()
                    vm.markRequestsAsRead()
                    dismiss()
                }
                .hCentered()
            }
   
            Section {
                HStack {
                    Text("Missing messages?")
                    Button("Rescan") {
                        vm.rescanForMissingDMs(36)
                        dismiss()
                    }
                }
                .hCentered()
            }

            if (vm.unreadNewRequestsNotWoTCount > 0) {
                Section {
                    HStack {
                        Text("\(vm.unreadNewRequestsNotWoTCount) requests outside Web of Trust")
                        if vm.showNotWoT {
                            Button("Hide") {
                                vm.showNotWoT = false
                                dismiss()
                            }
                        }
                        else {
                            Button("Show") {
                                vm.showNotWoT = true
                                vm.tab = "Requests"
                                dismiss()
                            }
                        }
                    }
                    .hCentered()
                }
            }
            
            if (vm.hiddenDMs > 0) {
                Section {
                    HStack {
                        Text("\(vm.hiddenDMs) conversation(s) hidden by you")
                        Button("Unhide") {
                            withAnimation {
                                vm.unhideAll()
                            }
                            dismiss()
                        }
                    }
                    .hCentered()
                }
            }
            
            NavigationLink {
                UpgradeDMsSheet(accountPubkey: vm.accountPubkey)
            } label: {
                Text("Configure your DM relays...")
            }

        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Direct Message Settings")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                    dismiss()
                }
            }
        }
    }
    
    @State private var didLoad = false
}
