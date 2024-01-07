//
//  Kind10002ConfigurationWizard.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/11/2023.
//

import SwiftUI

struct Kind10002ConfigurationWizard: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var account: CloudAccount
    public var onDismiss: () -> Void
    
    @State private var step:Step = .intro
    @State private var isBack = false
    @State private var publishing = false
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\CloudRelay.createdAt_, order: .forward)],
        animation: .default)
    private var relays: FetchedResults<CloudRelay>
    
    private var allRelays:[CloudRelay] {
        Array(relays)
    }
    
    private var writeRelays:[CloudRelay] {
        relays.filter { $0.write && !$0.excludedPubkeys.contains(account.publicKey) }
    }
    
    private var readRelays:[CloudRelay] {
        relays.filter { $0.read }
    }
    
    @State private var selectedReadRelays:Set<CloudRelay> = []
    @State private var selectedWriteRelays:Set<CloudRelay> = []
    
    private var allSelectedRelays:[CloudRelay] {
        Array(selectedReadRelays.union(selectedWriteRelays))
    }
    
    enum Step {
        case intro
        case selectWrite
        case selectRead
        case confirm
    }
    
    @Namespace private var intro
    @Namespace private var selecteWrite
    @Namespace private var selectRead
    @Namespace private var confirm
    
    
    var body: some View {
        ZStack {
            switch step {
            case .intro:
                Form {
                    Text("These steps help you let others know on which relays they can find \(account.anyName)'s posts and which relays others should use to reach \(account.anyName).")
                    
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Next") {
                            isBack = false
                            withAnimation {
                                step = .selectWrite
                            }
                        }
                    }
                }
                .id(intro)
                .transition(AnyTransition.asymmetric(
                                insertion:.move(edge: isBack ? .leading : .trailing),
                                removal: .move(edge: isBack ? .trailing : .leading))
                            )
            case .selectWrite:
                Form {
                    Section("Relays you post to") {
                        
                        Text("Which relays should others use to find posts for account: \(account.anyName)? (choose 3 max)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        RelaySelector(availableRelays: allRelays, selectedRelays: $selectedWriteRelays)
                    }
                    
                    Section("Tip") {
                        Text("Choose a popular relay so people can easily find your posts and choose an alternative relay, preferably your own, where people can always find your posts in case the popular relay has issues.")
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") {
                            isBack = true
                            withAnimation {
                                step = .intro
                            }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Next") {
                            isBack = false
                            withAnimation {
                                step = .selectRead
                            }
                        }
                    }
                }
                .id(selecteWrite)
                .transition(AnyTransition.asymmetric(
                                insertion:.move(edge: isBack ? .leading : .trailing),
                                removal: .move(edge: isBack ? .trailing : .leading))
                            )
            case .selectRead:
                Form {
                    Section("Relays you read from") {
                        Text("Which relays should others use to reach account: \(account.anyName)? (choose 3 max)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        RelaySelector(availableRelays: allRelays, selectedRelays: $selectedReadRelays)
                    }
                    
                    Section("Tip") {
                        Text("Choose one or more public relays you read from so you can receive notifications when others mention you.")
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") {
                            isBack = true
                            withAnimation {
                                step = .selectWrite
                            }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Next") {
                            isBack = false
                            withAnimation {
                                step = .confirm
                            }
                        }
                    }
                }
                .id(selectRead)
                .transition(AnyTransition.asymmetric(
                                insertion:.move(edge: isBack ? .leading : .trailing),
                                removal: .move(edge: isBack ? .trailing : .leading))
                            )
            case .confirm:
                Form {
                    Text("Based on your selection, the following relay set will be published so others can reach account: \(account.anyName).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    PublishedRelaySet(allSelectedRelays: allSelectedRelays, readRelays: selectedReadRelays, writeRelays: selectedWriteRelays)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") {
                            isBack = true
                            withAnimation {
                                step = .selectRead
                            }
                        }
                        .disabled(publishing)
                        .opacity(publishing ? 0.5 : 1.0)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Publish") {
                            publish()
                        }
                        .disabled(publishing)
                        .opacity(publishing ? 0.5 : 1.0)
                    }
                }
                .id(confirm)
                .transition(AnyTransition.asymmetric(
                                insertion:.move(edge: isBack ? .leading : .trailing),
                                removal: .move(edge: isBack ? .trailing : .leading))
                            )
            }
        }
    }
    
    private func publish() {
        account.accountRelays = Set(allSelectedRelays.map {
            AccountRelayData(url: ($0.url_ ?? ""),
                             read: selectedReadRelays.contains($0),
                             write: selectedWriteRelays.contains($0)
            )}
        )
        var kind10002 = NEvent(content: "")
        kind10002.kind = .relayList
        
        kind10002.tags = account.accountRelays
            .compactMap { relay in
                if relay.read && relay.write {
                    return NostrTag(["r", relay.url])
                }
                else if relay.read {
                    return NostrTag(["r", relay.url, "read"])
                }
                else if relay.write {
                    return NostrTag(["r", relay.url, "write"])
                }
                return nil
            }
        
        if account.isNC {
            kind10002.publicKey = account.publicKey
            kind10002 = kind10002.withId()
            
            // Save unsigned event:
            bg().perform {
                let savedEvent = Event.saveEvent(event: kind10002, flags: "nsecbunker_unsigned")
                DataProvider.shared().bgSave()
                onDismiss()
                dismiss()
                DispatchQueue.main.async {
                    NSecBunkerManager.shared.requestSignature(forEvent: kind10002, usingAccount: account, whenSigned: { signedEvent in
                        bg().perform {
                            savedEvent.sig = signedEvent.signature
                            savedEvent.flags = ""
                            DispatchQueue.main.async {
                                Unpublisher.shared.publishNow(signedEvent)
                            }
                        }
                    })
                }
            }
        }
        else if let signedEvent = try? account.signEvent(kind10002) {
            bg().perform {
                _ = Event.saveEvent(event: signedEvent)
                DataProvider.shared().bgSave()
                onDismiss()
                dismiss()
                DispatchQueue.main.async {
                    Unpublisher.shared.publishNow(signedEvent)
                }
            }
        }
        
    }
}

import NavigationBackport

#Preview {
    PreviewContainer({ pe in
        pe.loadRelays()
    }) {
        if let account = PreviewFetcher.fetchAccount() {
            NBNavigationStack {
                Kind10002ConfigurationWizard(account: account, onDismiss: { })
            }
        }
    }
}


struct RelaySelector: View {
    @EnvironmentObject private var themes:Themes
    public var availableRelays:[CloudRelay]
    @Binding public var selectedRelays:Set<CloudRelay>
    
    var body: some View {
        ForEach(availableRelays) { relay in
            Button {
                if selectedRelays.contains(relay) {
                    selectedRelays.remove(relay)
                }
                else {
                    selectedRelays.insert(relay)
                }
            } label: {
                HStack(alignment: .top) {
                    if selectedRelays.contains(relay) {
                        Image(systemName:  "checkmark.circle.fill")
                    }
                    else {
                        Image(systemName:  "circle")
                            .foregroundColor(Color.secondary)
                    }
                    Text(relay.url_ ?? "(no relay url)")
//                                .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundColor(selectedRelays.count >= 3 && !selectedRelays.contains(relay) ? .secondary : .primary)
                }
                .contentShape(Rectangle())
            }
            .disabled(selectedRelays.count >= 3 && !selectedRelays.contains(relay))
        }
    }
}

struct PublishedRelaySet: View {
    public var allSelectedRelays:[CloudRelay]
    public var readRelays:Set<CloudRelay>
    public var writeRelays:Set<CloudRelay>
    
    var body: some View {
        ForEach(allSelectedRelays) { selectedRelay in
            if readRelays.contains(selectedRelay) && writeRelays.contains(selectedRelay) {
                HStack {
                    Text(selectedRelay.url_ ?? "(no relay url)")
                    Spacer()
                    Text("read + write")
                        .foregroundColor(.secondary)
                }
            }
            else if readRelays.contains(selectedRelay) {
                HStack {
                    Text(selectedRelay.url_ ?? "(no relay url)")
                    Spacer()
                    Text("read + write")
                        .foregroundColor(.secondary)
                }
            }
            else if writeRelays.contains(selectedRelay) {
                HStack {
                    Text(selectedRelay.url_ ?? "(no relay url)")
                    Spacer()
                    Text("read + write")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
