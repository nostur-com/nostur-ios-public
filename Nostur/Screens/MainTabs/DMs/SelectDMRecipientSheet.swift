//
//  NewDM.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/03/2023.
//

import SwiftUI
import NostrEssentials

struct SelectDMRecipientSheet: View {
    @Environment(\.dismiss) private var dismiss
    // from account
    let accountPubkey: String
    var onSelect: (Set<String>) -> Void // pubkeys
    
    @State private var viewState: ViewState = .contactSelection
    @State var backlog = Backlog(timeout: 10, auto: true, backlogDebugName: "SelectDMRecipientSheet")
    
    var body: some View {
        Container {
            switch viewState {
            case .contactSelection:
                ContactsSearch(
                    followingPubkeys: account(by: accountPubkey)?.followingPubkeys ?? [],
                    prompt: "Search contacts",
                    doneButtonText: "Start",
                    disabledPubkeys: [accountPubkey],
                    onSelectContacts: { selectedContacts in
                        if selectedContacts.count == 1 {
                            Task { @MainActor in
                                onSelect(Set(selectedContacts.map { $0.pubkey }))
                                dismiss()
                            }
                        }
                        else {
                            Task { @MainActor in
                                self.viewState = .checkingDMrelays(Set(selectedContacts.map { $0.pubkey }))
                            }
                        }
                    }
                )
                .padding(.top, 10)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") {
                            dismiss()
                        }
                    }
                }
                
            case .checkingDMrelays(let pubkeys):
                CenteredProgressView(message: "Looking up DM relays of selected contacts...")
                    .task {
                        checkDMRelays(pubkeys)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel", systemImage: "xmark") {
                                dismiss()
                            }
                        }
                    }
            case .missingDMRelays(let pubkeys):
                VStack(alignment: .center) {
                    Text("Could not find DM relays for:")
                    ForEach(pubkeys.sorted(), id: \.self) { pubkey in
                        PFPandName(pubkey: pubkey)
                    }
                    Text("All participants need to have their DM relays published to start a group chat.")
                        .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back", systemImage: "chevron.left") {
                            self.viewState = .contactSelection
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized:"Private conversation", comment:"Navigation title for screen to select a contact to send a Direct Message to"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func checkDMRelays(_ pubkeys: Set<String>) {
        let reqTask = ReqTask(debounceTime: 2.0, subscriptionId: "SUPP17-") { taskId in
            nxReq(Filters(
                kinds: [10050],
                limit: 200
            ), subscriptionId: taskId, isActiveSubscription: false, useOutbox: true)
        } processResponseCommand: { taskId, _, _ in
            Task {
                var missingDMrelays: Set<String> = []
                for pubkey in pubkeys {
                    let relays = await getDMrelays(for: pubkey)
                    if relays.isEmpty {
                        missingDMrelays.insert(pubkey)
                    }
                }
                Task { @MainActor in
                    if !missingDMrelays.isEmpty {
                        self.viewState = .missingDMRelays(missingDMrelays)
                    }
                    else {
                        onSelect(pubkeys)
                        dismiss()
                    }
                }
                backlog.clear()
            }
        } timeoutCommand: { taskId in
            Task {
                var missingDMrelays: Set<String> = []
                for pubkey in pubkeys {
                    let relays = await getDMrelays(for: pubkey)
                    if relays.isEmpty {
                        missingDMrelays.insert(pubkey)
                    }
                }
                Task { @MainActor in
                    if !missingDMrelays.isEmpty {
                        self.viewState = .missingDMRelays(missingDMrelays)
                    }
                    else {
                        onSelect(pubkeys)
                        dismiss()
                    }
                }
                backlog.clear()
            }
        }
        Backlog.shared.add(reqTask)
        reqTask.fetch()
    }
    
    private enum ViewState {
        case contactSelection
        case checkingDMrelays(Set<String>) // pubkeys
        case missingDMRelays(Set<String>) // pubkeys
    }
}
