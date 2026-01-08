//
//  DMConversationInfoSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/12/2025.
//

import SwiftUI
import NostrEssentials

struct DMConversationInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: ConversionVM

    @State private var viewState: ViewState = .checkingDMrelays
    @State private var useImprovedFormat = false
    @State private var relaysPerPubkey: [String: Set<String>] = [:] // [pubkey: Set<relayString>]

    @State var backlog = Backlog(timeout: 10, auto: true, backlogDebugName: "SelectDMRecipientSheet")
    
    var body: some View {
        NXForm {
            if vm.conversationVersion == 17 {
                Section {
                    if viewState == .checkingDMrelays {
                        CenteredProgressView(message: "Looking up DM relays...")
                            .task {
                                checkDMRelays(vm.participants)
                            }
                    }
                    else {
                        VStack(alignment: .leading) {
                            ForEach(relaysPerPubkey.keys.sorted(), id: \.self) { key in
                                PFPandName(pubkey: key)
                                    .padding(.top, 10)
                                
                                ForEach(relaysPerPubkey[key]!.sorted(), id: \.self) { relay in
                                    Text(relay)
                                }
                            }
                        }
                    }
                } header: {
                    Text("DM relays")
                }
                
                if vm.participants.count <= 2 {
                    Section {
                        Toggle(isOn: $useImprovedFormat) {
                            VStack(alignment: .leading) {
                                Text("Increase privacy")
                                Text("Switch to a more private DM format (NIP-17) for new messages")
                                    .font(.footnote)
                                    .foregroundColor(Color.gray)
                            }
                        }
                    } header: {
                        Text("Message format")
                    }
                }
            }
            else if vm.conversationVersion == 4 {
                switch viewState {
                case .checkingDMrelays:
                    Section {
                        CenteredProgressView(message: "Looking up DM relays...")
                            .task {
                                checkDMRelays(vm.participants)
                            }
                    } header: {
                        Text("Message format")
                    }

                case .missingDMRelays(let pubkeys):
                    Section {
                        VStack(alignment: .leading) {
                            Text("Using NIP-04")
                            
                            Text("Messages are sent using an older encryption protocol because the recipients private message relays have not been published or could not be found.")
                                .font(.footnote)
                                .padding(.top, 10)
                        }
                        
                        
                        VStack(alignment: .leading) {
                            Text("Could not find DM relays for:")
                                .padding(.top, 10)
                            
                            ForEach(pubkeys.sorted(), id: \.self) { pubkey in
                                PFPandName(pubkey: pubkey)
                            }
                        }
                    } header: {
                        Text("Message format")
                    }
                case .offerUpgrade:
                    Section {
                        VStack(alignment: .leading) {
                            Text("Using NIP-04")
                            
                            Text("Messages are sent using an older encryption protocol.")
                                .padding(.top, 10)
                        }
                        
                        Toggle(isOn: $useImprovedFormat) {
                            VStack(alignment: .leading) {
                                Text("Increase privacy")
                                Text("Switch to a more private DM format (NIP-17) for new messages")
                                    .font(.footnote)
                                    .foregroundColor(Color.gray)
                            }
                        }
                    } header: {
                        Text("Message format")
                    }
                }
            }
        }
        .onAppear {
            if vm.conversationVersion == 17 {
                useImprovedFormat = true
            }
        }
        .onValueChange(useImprovedFormat) { oldValue, newValue in
            if !oldValue && newValue {
                vm.conversationVersion = 17
                vm.dmState?.version = 17
            }
            else if !newValue {
                vm.conversationVersion = 4
                vm.dmState?.version = 0
            }
        }
        .navigationTitle(String(localized:"Conversation info", comment:"Navigation title for screen with DM conversation info"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                    dismiss()
                }
            }
        }
    }
    
    private func checkDMRelays(_ pubkeys: Set<String>) {
        let reqTask = ReqTask(debounceTime: 2.5, subscriptionId: "SUPP17I-") { taskId in
            nxReq(Filters(
                authors: pubkeys,
                kinds: [10050],
                limit: 200
            ), subscriptionId: taskId, isActiveSubscription: false, relayType: .READ, useOutbox: true)
            nxReq(Filters(
                authors: pubkeys,
                kinds: [10050],
                limit: 200
            ), subscriptionId: "SUPP17I-S2-", isActiveSubscription: false, relayType: .SEARCH_ONLY)
        } processResponseCommand: { taskId, _, _ in
            Task {
                var missingDMrelays: Set<String> = []
                for pubkey in pubkeys {
                    let relays = await getDMrelays(for: pubkey)
                    relaysPerPubkey[pubkey] = relays
                    if relays.isEmpty {
                        missingDMrelays.insert(pubkey)
                    }
                }
                Task { @MainActor in
                    if !missingDMrelays.isEmpty {
                        self.viewState = .missingDMRelays(missingDMrelays)
                    }
                    else {
                        self.viewState = .offerUpgrade
                    }
                }
                backlog.clear()
            }
        } timeoutCommand: { taskId in
            Task {
                var missingDMrelays: Set<String> = []
                for pubkey in pubkeys {
                    let relays = await getDMrelays(for: pubkey)
                    relaysPerPubkey[pubkey] = relays
                    if relays.isEmpty {
                        missingDMrelays.insert(pubkey)
                    }
                }
                Task { @MainActor in
                    if !missingDMrelays.isEmpty {
                        self.viewState = .missingDMRelays(missingDMrelays)
                    }
                    else {
                        self.viewState = .offerUpgrade
                    }
                }
                backlog.clear()
            }
        }
        Backlog.shared.add(reqTask)
        reqTask.fetch()
    }
    
    private enum ViewState: Equatable {
        case checkingDMrelays
        case missingDMRelays(Set<String>) // pubkeys
        case offerUpgrade
    }
}
