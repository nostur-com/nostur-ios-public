//
//  Settings+BlossomServerList.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/05/2025.
//

import SwiftUI
import NavigationBackport
import NostrEssentials

struct BlossomServerList: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    
    @ObservedObject private var settings: SettingsStore = .shared
    @State private var newServerSheet = false
    @State private var account: CloudAccount? = nil
    
    
    
    @State private var okId: String? = nil
    @State private var isPublishing = false
    @State private var publishedToRelays: [String] = []
    
    
    @State private var checkingRelays = false
    @State private var serverList: [String] = []
    
    var body: some View {
        NXForm {
            Section {
                if checkingRelays {
                    Text("Checking relays for your blossom server list...")
                }
                else {
                    ForEach(serverList, id: \.self) { server in
                        Text(server)
                            .id(server)
                    }
                    .onMove(perform: { indices, newOffset in
                        // set new serverList offsets:
                        serverList.move(fromOffsets: indices, toOffset: newOffset)
                    })
                    .onDelete { indexSet in
                        serverList.remove(atOffsets: indexSet)
                    }
                    
                    HStack {
                        Image(systemName: "plus.circle")
                            .foregroundColor(Color.secondary)
                        Text("Add Blossom server")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        newServerSheet = true
                    }
                }
            } header: {
                Text("Blossom servers")
            } footer: {
                if serverList.count > 1 {
                    Text("Servers higher on the list will be used first")
                }
            }
            .listRowBackground(theme.background)
            
            if let account, !serverList.isEmpty {
                Section {
                    if !publishedToRelays.isEmpty {
                        Text("Published to:")
                        ForEach(publishedToRelays, id: \.self) { relay in
                            Text(relay)
                        }
                    }
                    else if isPublishing {
                        ProgressView()
                    }
                    else {
                        HStack {
                            AccountPFP(account: account, size: 25)
                            Button("Publish list now") { publishBlossomList() }
                            Spacer()
                        }
                    }
                } header: {
                    Text("Publish to relays")
                } footer: {
                    Text("Let others know on which servers your media can be found")
                }
            }
        }

        .toolbar {
            
            ToolbarItem(placement: .navigationBarTrailing) {
                if !serverList.isEmpty {
                    EditButton()
                }
            }
            
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                    SettingsStore.shared.blossomServerList = serverList
                    dismiss()
                }
                .accessibilityLabel(String(localized:"Add media server", comment: "Button to add a new media server"))
            }
        }
        .sheet(isPresented: $newServerSheet) {
            NBNavigationStack {
                AddBlossomServerSheet(onAdd: { serverUrlString in
                    serverList.insert(serverUrlString, at: 0)
                    SettingsStore.shared.blossomServerList = serverList 
                })
                    .environment(\.theme, theme)
            }
            .presentationBackgroundCompat(theme.listBackground)
        }
        .onAppear {
            if let account = Nostur.account(), account.isFullAccount {
                self.account = account
            }
            serverList = SettingsStore.shared.blossomServerList
            if serverList.isEmpty {
                checkForUserServerListOnRelays()
            }
        }
        .onDisappear {
            SettingsStore.shared.blossomServerList = serverList
            if let removeNoDbEventId {
                bg().perform {
                    // Remove so we can process it again next time (its not saved in DB)
                    Importer.shared.existingIds[removeNoDbEventId] = nil
                }
            }
        }
        
        
        .onChange(of: serverList) { newServerList in
            // Reset if list is updated, so user can publish again if needed
            publishedToRelays = []
        }
        
        .onReceive(MessageParser.shared.okSub.receive(on: RunLoop.main)) { okMessage in
            // okMessage = (id: String, relay: String)
            guard let okId else { return }
            if okMessage.id == okId {
                publishedToRelays.append(okMessage.relay)
                isPublishing = false
            }
        }
    }
    
    private func publishBlossomList() {
        guard let account = self.account else { return }
        var userServerList = NEvent(kind: .blossomServerList, tags: serverList.map {
            NostrTag(["server", $0])
        })
        
        isPublishing = true
        
        if account.isNC {
            userServerList.publicKey = account.publicKey
            userServerList = userServerList.withId()
            self.okId = userServerList.id
            RemoteSignerManager.shared.requestSignature(forEvent: userServerList, usingAccount: account, whenSigned: { signedEvent in
                Unpublisher.shared.publishNow(signedEvent, skipDB: true)
            })
        }
        else {
            guard let userServerListSigned = try? account.signEvent(userServerList)
            else { return }
            self.okId = userServerListSigned.id
            Unpublisher.shared.publishNow(userServerListSigned, skipDB: true)
        }
    }
    
    @State private var removeNoDbEventId: String? = nil
    
    private func checkForUserServerListOnRelays() {
        guard let account = account else { return }
        let pubkey = account.publicKey
        checkingRelays = true
        let task = ReqTask(
            debounceTime: 0.02,
            timeout: 7.0,
            subscriptionId: "-DB-10063",
            reqCommand: { taskId in
                nxReq(Filters(authors: [account.publicKey], kinds: [10063]), subscriptionId: taskId)    
            }, processResponseCommand: { taskId, relayMessage, event in
                if let nEvent = relayMessage?.event {
                    checkingRelays = false
                    serverList = nEvent.tags.filter {
                        $0.type == "server" && $0.value != ""
                    }
                    .map { $0.value }
                    if serverList.isEmpty {
                        newServerSheet = true
                    }
                    bg().perform {
                        // Remove so we can process it again next time (its not saved in DB)
                        Importer.shared.existingIds[nEvent.id] = nil
                    }
                }
                else {
                    bg().perform {
                        if let userListEvent = Event.fetchEventsBy(pubkey: pubkey, andKind: 10063, context: bg()).first {
                            
                            let servers = userListEvent.tags().filter {
                                $0.type == "server" && $0.value != ""
                            }
                            .map { $0.value }
                            
                            Task { @MainActor in
                                checkingRelays = false
                                serverList = servers
                                if serverList.isEmpty {
                                    newServerSheet = true
                                }
                            }
                        }
                        else {
                            Task { @MainActor in
                                checkingRelays = false
                                newServerSheet = true
                            }
                        }
                    }
                }
                
            }, timeoutCommand: { taskId in
                checkingRelays = false
                newServerSheet = true
            }
        )
        
        Backlog.shared.add(task)
        task.fetch()
    }
}

#Preview("Blossom server list") {
    PreviewContainer({ pe in
        pe.loadAccount()
    }) {
        NBNavigationStack {
            BlossomServerList()
        }
    }
}
