//
//  RelayMastery.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/11/2023.
//

import SwiftUI
import NavigationBackport

struct RelayMastery: View {
    @EnvironmentObject private var dim: DIMENSIONS
    @Environment(\.theme) private var theme
    
    public var relays: [CloudRelay]
    
    @State private var accountTab: String = ""
    @State private var accounts: [CloudAccount] = []
    
    var body: some View {
        VStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
//                        TabButton(
//                            action: { accountTab = "SHARED" },
//                            title: String(localized:"Relays", comment:"Tab title for relay mastery"),
//                            selected: accountTab == "SHARED")
//                        Spacer()
                        
                        ForEach(accounts) { account in
                            TabButton(
                                action: { accountTab = account.publicKey },
                                title: account.anyName,
                                selected: accountTab == account.publicKey )
                            Spacer()
                        }
                    }
                    .frame(minWidth: dim.listWidth)
                    .background(theme.listBackground)
                }
               
                ZStack {
                    theme.listBackground // needed to give this ZStack and parents size, else weird startup animation sometimes
                    
//                    SharedRelaySettings(relays: relays)
//                        .opacity(accountTab == "SHARED" ? 1 : 0)
                    
                    ForEach(accounts) { account in
                        if accountTab == account.publicKey {
                            AccountRelaySettings(accountPubkey: account.publicKey, relays: relays, account: account)
                        }
                        else {
                            EmptyView()
                        }
                    }
                }
                
            }
        }
        .navigationTitle("Announced relays")
        .task {
            accounts = AccountsState.shared.accounts
                .filter { $0.isFullAccount }
                .sorted(by: { $0.lastLoginAt > $1.lastLoginAt })
            
            if accountTab == "", let firstAccountPubkey = accounts.first?.publicKey {
                accountTab = firstAccountPubkey
            }
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadRelays()
        pe.loadAccounts()
    }) {
        let relays = PreviewFetcher.fetchRelays()
        RelayMastery(relays: relays)
    }
}


//struct SharedRelaySettings: View {
//    @Environment(\.theme) private var theme
//    public var relays: [CloudRelay] = []
//    @State var editRelay: CloudRelay?
//    
//    var body: some View {
//        Form {
//            Text("These relays are used for all accounts, and are not announced unless configured on the account specific settings.")
//            
//            Section(header: Text("Relays", comment: "Relay settings heading")) {
//                ForEach(relays) { relay in
//                    RelayRowView(relay: relay)
//                        .onTapGesture {
//                            editRelay = relay
//                        }
//                }
//            }
//        }
//        .listStyle(.plain)
//        .lineSpacing(0)
//        .listRowInsets(.none)
//        .listSectionSeparator(.hidden)
//        .sheet(item: $editRelay, content: { relay in
//            NBNavigationStack {
//                RelayEditView(relay: relay)
//                    .environment(\.theme, theme)
//            }
//            .nbUseNavigationStack(.never)
//            .presentationBackgroundCompat(theme.listBackground)
//        })
//    }
//}

struct AccountRelaySettings: View {
    @Environment(\.theme) private var theme
    public var accountPubkey: String
    public var relays: [CloudRelay] = []
    @ObservedObject public var account: CloudAccount
    
    @State private var showWizard = false
    
    @StateObject private var vm = FetchVM<[AccountRelayData]>(timeout: 1.5, debounceTime: 0.05)
    
    var body: some View {
        NXForm {
            switch vm.state {
            case .initializing, .loading, .altLoading:
                self.loadingView
            case .ready(let accountRelays):
                Section("Announced relays for \(account.anyName)") {
                    ForEach(accountRelays) { relay in
                        if (relay.read && relay.write) {
                            HStack {
                                Text(relay.url)
                                Spacer()
                                Text("read + write")
                                    .foregroundColor(.secondary)
                            }
                        }
                        else if (relay.read) {
                            HStack {
                                Text(relay.url)
                                Spacer()
                                Text("read")
                                    .foregroundColor(.secondary)
                            }
                        }
                        else if (relay.write) {
                            HStack {
                                Text(relay.url)
                                Spacer()
                                Text("write")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Button("Reconfigure announced relays...") {
                        showWizard = true
                    }
                }
            case .timeout:
                self.timeoutView
            case .error(let error):
                Text(error)
            }
        }
        .sheet(isPresented: $showWizard, content: {
            NBNavigationStack {
                Kind10002ConfigurationWizard(account: account, onDismiss: onDismiss)
                    .navigationTitle("Announced relays")
                    .navigationBarTitleDisplayMode(.inline)
                    .environment(\.theme, theme)
            }
            .nbUseNavigationStack(.never)
        })
    }
    
    @ViewBuilder
    private var loadingView: some View {
        Section("Announced relays for \(account.anyName)") {
            Text("\(Image(systemName: "hourglass.circle.fill")) Checking relays...")
                .onAppear { [weak vm, weak account] in
                    guard let vm, let account else { return }
                    if !account.accountRelays.isEmpty {
                        vm.ready(Array(account.accountRelays))
                    }
                    else {
                        vm.setFetchParams((
                            prio: false,
                            req: { [weak vm] _ in
                                bg().perform { // 1. FIRST CHECK LOCAL DB
                                    guard let vm else { return }
                                    if let kind10002 = Event.fetchReplacableEvent(10002, pubkey: accountPubkey, context: bg()) {
                                        
                                        let relays:[AccountRelayData] = kind10002.tags().compactMap { tag in
                                            if (tag.type != "r") { return nil }
                                            if (tag.tag.count == 2) {
                                                return AccountRelayData(url: tag.value, read: true, write: true)
                                            }
                                            else if (tag.tag.count >= 3) {
                                                if tag.tag[2] == "read" {
                                                    return AccountRelayData(url: tag.value, read: true, write: false)
                                                }
                                                else if tag.tag[2] == "write" {
                                                    return AccountRelayData(url: tag.value, read: false, write: true)
                                                }
                                            }
                                            return nil
                                        }
                                        vm.ready(relays)
                                        DispatchQueue.main.async { [weak account] in
                                            guard let account else { return }
                                            account.accountRelays = Set(relays)
                                            DataProvider.shared().save()
                                        }
                                    }
                                    else { req(RM.getRelays(pubkeys: [accountPubkey])) }
                                }
                            },
                            onComplete: { [weak vm] relayMessage, _ in
                                bg().perform { // 3. WE SHOULD HAVE IT IN LOCAL DB NOW
                                    guard let vm else { return }
                                    if let kind10002 = Event.fetchReplacableEvent(10002, pubkey: accountPubkey, context: bg()) {
                                        let relays:[AccountRelayData] = kind10002.tags().compactMap { tag in
                                            if (tag.type != "r") { return nil }
                                            if (tag.tag.count == 2) {
                                                return AccountRelayData(url: tag.value, read: true, write: true)
                                            }
                                            else if (tag.tag.count >= 3) {
                                                if tag.tag[2] == "read" {
                                                    return AccountRelayData(url: tag.value, read: true, write: false)
                                                }
                                                else if tag.tag[2] == "write" {
                                                    return AccountRelayData(url: tag.value, read: false, write: true)
                                                }
                                            }
                                            return nil
                                        }
                                        vm.ready(relays)
                                        DispatchQueue.main.async { [weak account] in
                                            guard let account else { return }
                                            account.accountRelays = Set(relays)
                                            DataProvider.shared().save()
                                        }
                                    }
                                    else { vm.timeout() }
                                }
                            },
                            altReq: nil
                        ))
                        vm.fetch()
                    }
                }
        }
    }
    
    @ViewBuilder
    private var timeoutView: some View {
        Section("Announced relays for \(account.anyName)") {
            Button("Configure announced relays") {
                showWizard = true
            }
        }
    }
    
    private func onDismiss() {
        DispatchQueue.main.async {
            vm.state = .loading; vm.fetch()
        }
    }
}
