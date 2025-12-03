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
    
    @State private var step: Step = .intro
    @State private var isBack = false
    @State private var publishing = false
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\CloudRelay.createdAt_, order: .forward)],
        animation: .default)
    private var relays: FetchedResults<CloudRelay>
    
    private var allRelays: [CloudRelay] {
        Array(relays)
    }
    
    private var writeRelays: [CloudRelay] {
        relays.filter { $0.write && !$0.excludedPubkeys.contains(account.publicKey) }
    }
    
    private var readRelays: [CloudRelay] {
        relays.filter { $0.read }
    }
    
    private var dmRelays: [CloudRelay] {
        relays.filter { $0.auth }
    }
    
    @State private var selectedReadRelays: Set<CloudRelay> = []
    @State private var selectedWriteRelays: Set<CloudRelay> = []
    @State private var selectedDMRelays: Set<CloudRelay> = []
    
    private var allSelectedRelays: [CloudRelay] {
        Array(selectedReadRelays.union(selectedWriteRelays).union(selectedDMRelays))
    }
    
    enum Step {
        case intro
        case selectWrite
        case selectRead
        case selectDM
        case confirm
    }
    
    @Namespace private var intro
    @Namespace private var selectWrite
    @Namespace private var selectRead
    @Namespace private var selectDM
    @Namespace private var confirm
    
    
    var body: some View {
        ZStack {
            switch step {
            case .intro:
                NXForm {
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
                NXForm {
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
                .id(selectWrite)
                .transition(AnyTransition.asymmetric(
                                insertion:.move(edge: isBack ? .leading : .trailing),
                                removal: .move(edge: isBack ? .trailing : .leading))
                            )
            case .selectRead:
                NXForm {
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
                                step = .selectDM
                            }
                        }
                    }
                }
                .id(selectRead)
                .transition(AnyTransition.asymmetric(
                                insertion:.move(edge: isBack ? .leading : .trailing),
                                removal: .move(edge: isBack ? .trailing : .leading))
                            )
            case .selectDM:
                NXForm {
                    Section("Relays to receive private message") {
                        Text("Which relays should others use to send private messages to \(account.anyName)? (choose 3 max)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        RelaySelector(availableRelays: allRelays, selectedRelays: $selectedDMRelays)
                    }
                    
                    Section("Tip") {
                        Text("Choose a relay that requires authentication to receive private messages.")
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") {
                            isBack = true
                            withAnimation {
                                step = .selectRead
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
                .id(selectDM)
                .transition(AnyTransition.asymmetric(
                                insertion:.move(edge: isBack ? .leading : .trailing),
                                removal: .move(edge: isBack ? .trailing : .leading))
                            )
            case .confirm:
                NXForm {
                    Section {
                        PublishedRelaySet(allSelectedRelays: allSelectedRelays, readRelays: selectedReadRelays, writeRelays: selectedWriteRelays, dmRelays: selectedDMRelays)
                    } header: {
                        Text("Based on your selection, the following relay set will be published so others can reach account: \(account.anyName).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } footer: {
                        VStack(alignment: .leading) {
                            Text("read: you read from this relay, so others should post there.")
                                .font(.footnote)
                            Text("write: you post to this relay, so others read from there.")
                                .font(.footnote)
                            Text("dm: you receive private message from this relay, so others should send private messages there.")
                                .font(.footnote)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") {
                            isBack = true
                            withAnimation {
                                step = .selectDM
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
                             write: selectedWriteRelays.contains($0),
                             dm: selectedDMRelays.contains($0)
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
        
        var kind10050 = NEvent(content: "")
        kind10050.kind = .dmRelayList
        
        kind10050.tags = account.accountRelays
            .compactMap { relay in
                if relay.dm {
                    return NostrTag(["relay", relay.url])
                }
                return nil
            }
        
        if account.isNC {
            kind10002.publicKey = account.publicKey
            kind10002 = kind10002.withId()
            
            kind10050.publicKey = account.publicKey
            kind10050 = kind10050.withId()
            
            // Save unsigned event:
            let bgContext = bg()
            bgContext.perform {
                let savedEvent10002 = Event.saveEvent(event: kind10002, flags: "nsecbunker_unsigned", context: bgContext)
                let savedEvent10050 = Event.saveEvent(event: kind10050, flags: "nsecbunker_unsigned", context: bgContext)
                DataProvider.shared().saveToDiskNow(.bgContext)
                onDismiss()
                dismiss()
                DispatchQueue.main.async {
                    NSecBunkerManager.shared.requestSignature(forEvent: kind10002, usingAccount: account, whenSigned: { signedEvent10002 in
                        bgContext.perform {
                            savedEvent10002.sig = signedEvent10002.signature
                            savedEvent10002.flags = ""
                            DispatchQueue.main.async {
                                Unpublisher.shared.publishNow(signedEvent10002)
                            }
                        }
                    })
                    NSecBunkerManager.shared.requestSignature(forEvent: kind10050, usingAccount: account, whenSigned: { signedEvent10050 in
                        bgContext.perform {
                            savedEvent10050.sig = signedEvent10050.signature
                            savedEvent10050.flags = ""
                            DispatchQueue.main.async {
                                Unpublisher.shared.publishNow(signedEvent10050)
                            }
                        }
                    })
                }
            }
        }
        else {
            if let signedEvent10002 = try? account.signEvent(kind10002) {
                let bgContext = bg()
                bgContext.perform {
                    _ = Event.saveEvent(event: signedEvent10002, context: bgContext)
                    DataProvider.shared().saveToDiskNow(.bgContext)
                    onDismiss()
                    dismiss()
                    DispatchQueue.main.async {
                        Unpublisher.shared.publishNow(signedEvent10002)
                    }
                }
            }
            
            if let signedEvent10050 = try? account.signEvent(kind10050) {
                let bgContext = bg()
                bgContext.perform {
                    _ = Event.saveEvent(event: signedEvent10050, context: bgContext)
                    DataProvider.shared().saveToDiskNow(.bgContext)
                    onDismiss()
                    dismiss()
                    DispatchQueue.main.async {
                        Unpublisher.shared.publishNow(signedEvent10050)
                    }
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
    @Environment(\.theme) private var theme
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
    public var allSelectedRelays: [CloudRelay]
    public var readRelays: Set<CloudRelay>
    public var writeRelays: Set<CloudRelay>
    public var dmRelays: Set<CloudRelay>
    
    var body: some View {
        ForEach(allSelectedRelays) { selectedRelay in
            HStack {
                Text(selectedRelay.url_ ?? "(no relay url)")
                Spacer()
                Text([readRelays.contains(selectedRelay) ? "read" : nil,
                      writeRelays.contains(selectedRelay) ? "write" : nil,
                       dmRelays.contains(selectedRelay) ? "dm" : nil].compactMap { $0 }
                          .joined(separator: " + "))
                    .foregroundColor(.secondary)
            }
        }
    }
}
