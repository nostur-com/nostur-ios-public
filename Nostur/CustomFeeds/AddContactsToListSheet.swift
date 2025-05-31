//
//  AddContactsToListSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/04/2025.
//

import SwiftUI
import NostrEssentials

struct AddContactsToListSheet: View {
    
    public var preSelectedContactPubkeys: Set<String> = []
    public let theme: Theme
    
    
    // only contact lists, not relay lists
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CloudFeed.createdAt, ascending: false)],
        predicate: NSPredicate(format: "type == %@ OR type == nil", ListType.pubkeys.rawValue),
        animation: .none)
    var lists: FetchedResults<CloudFeed>
    
    @StateObject private var vm = FetchVM<[NRContact]>(timeout: 3.5, debounceTime: 0.15)
    @State private var selectedContactPubkeys: Set<String> = []
    @State private var listName: String = ""
    @State private var showChooseListView = false
    @State private var selectedList: CloudFeed? = nil
    @FocusState private var isFocused: Bool
    
    var formIsValid: Bool {
        listName != "" && !selectedContactPubkeys.isEmpty
    }
        
    var body: some View {
        VStack {
            switch vm.state {
            case .initializing, .loading, .altLoading:
                HStack(spacing: 5) {
                    ProgressView()
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .center)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.lineColor, lineWidth: 1)
                )
                .onBecomingVisible {
                    load()
                }
                
            case .ready(let nrContacts):
                self.readyView(nrContacts)

            case .timeout:
                Text("Unable to fetch contacts")
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.lineColor, lineWidth: 1)
                    )
                
            case .error(let error):
                Text(error)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.lineColor, lineWidth: 1)
                    )
            }
        }
        .listRowBackground(theme.background)
    }
    
    @ViewBuilder
    private func readyView(_ nrContacts: [NRContact]) -> some View {
        ScrollView {
            if showChooseListView {
                LazyVStack {
                    ForEach(lists) { list in
                        HStack(spacing: 10) {
                            ListRow(list: list, showPin: false)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedList = list
                                    listName = list.name_
                                    showChooseListView = false
                                }
                        }
                    }
                    Divider()
                }
                .navigationTitle("Add to existing list")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(content: {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") {
                            showChooseListView = false
                        }
                    }
                })
            }
            else {
                LazyVStack(spacing: GUTTER) {
                    ForEach(nrContacts) { nrContact in
                        HStack(spacing: 10) {
                            Image(systemName: selectedContactPubkeys.contains(nrContact.pubkey) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedContactPubkeys.contains(nrContact.pubkey) ? theme.accent : Color.secondary)
                                .padding(.vertical, 10)
                                .layoutPriority(1)
                            
                            ObservedPFP(pubkey: nrContact.pubkey, nrContact: nrContact, size: 20)
                                .layoutPriority(2)
                            
                            Text(nrContact.anyName)
                                .lineLimit(1)
                                .layoutPriority(3)
                            
                            NewPossibleImposterLabel(nrContact: nrContact)
                                .layoutPriority(1)
                            
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedContactPubkeys.contains(nrContact.pubkey) {
                                selectedContactPubkeys.remove(nrContact.pubkey)
                            }
                            else {
                                selectedContactPubkeys.insert(nrContact.pubkey)
                            }
                        }
                        
                        Divider()
                    }
                }
                .navigationTitle(selectedList == nil ? "Add to new list" : "Add to existing list")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(content: {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            AppSheetsModel.shared.dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add (\(selectedContactPubkeys.count))") {
                            add()
                        }
                        .disabled(!formIsValid)
                        .opacity(!formIsValid ? 0.25 : 1.0)
                    }
                })
            }
        }
        .padding(.horizontal, 20)
        .safeAreaInset(edge: .top) {
            if !showChooseListView {
                Form {
                    Section {
                        TextField("New list name", text: $listName)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .focused($isFocused)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    isFocused = true
                                }
                            }
                            .disabled(selectedList != nil)
                            .listRowBackground(theme.listBackground)
                            .padding(.trailing, 150)
                            .overlay(alignment: .trailing) {
                                if selectedList == nil {
                                    Button("Choose existing list", systemImage: "folder") {
                                        showChooseListView = true
                                    }
                                    .labelStyle(.iconOnly)
                                }
                                else {
                                    Button("Clear", systemImage: "multiply.circle.fill") {
                                        selectedList = nil
                                        listName = ""
                                    }
                                    .labelStyle(.iconOnly)
                                }
                            }
                    } footer: {
                        if let selectedList, selectedList.sharedList {
                            Text("This list is public")
                                .font(.footnote)
                                .foregroundColor(Color.secondary)
                        }
                    }
                }
                .scrollDisabledCompat()
                .contentMarginsTopCompat(0)
                .listStyle(.plain)
                .frame(height: 80)
                
            }
//            else {
//                Text("Choose existing list")
//                    .font(.title2)
//                
//                
//            }
        }
    }
    
    private func load() {
        guard !preSelectedContactPubkeys.isEmpty else {
            vm.state = .ready([])
            return
        }
        
        selectedContactPubkeys = preSelectedContactPubkeys
        
        let fetchParams: FetchVM.FetchParams = (
            prio: false,
            req: { taskId in
                nxReq(Filters(authors: preSelectedContactPubkeys), subscriptionId: taskId)
            },
            onComplete: { relayMessage, _ in
                bg().perform {
                    let nrContacts: [NRContact] = preSelectedContactPubkeys.map { NRContact.instance(of: $0) }
                    if !nrContacts.isEmpty {
                        vm.ready(nrContacts)
                    }
                    else {
                        vm.timeout()
                    }
                }
            },
            altReq: nil
        )
        vm.setFetchParams(fetchParams)
        vm.fetch()
    }
    
    private func add() {
        guard formIsValid else { return }
        AppSheetsModel.shared.dismiss()
        // New list or existing list?
        let list = selectedList ?? CloudFeed(context: viewContext())
        if selectedList == nil {
            list.name = listName
            list.id = UUID()
            list.showAsTab = true
            list.createdAt = .now
            list.wotEnabled = false
            list.type = ListType.pubkeys.rawValue
            list.contactPubkeys = selectedContactPubkeys
            list.order = 0
            
            viewContextSave()
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadCloudFeeds()
    }) {
        let suggestedPubkeys: Set<String> = ["9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24","96a0b3e0738e7ff0838abc900fc48f61effef780d175a6bb2c0240246556bb3e"]
//        let suggestedPubkeys2: Set<String> = ["9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24","96a0b3e0738e7ff0838abc900fc48f61effef780d175a6bb2c0240246556bb3e","de14fe62f97e09429581f9e8fec3170f3ce5e7936a2134bf70c87c5ff229e53a","be1d89794bf92de5dd64c1e60f6a2c70c140abac9932418fee30c5c637fe9479","7fa56f5d6962ab1e3cd424e758c3002b8665f7b0d8dcee9fe9e288d7751ac194","460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c","77bbc321087905d98f941bd9d4cc4d2856fdc0f2f083f3ae167544e1a3b39e91","4eb88310d6b4ed95c6d66a395b3d3cf559b85faec8f7691dafd405a92e055d6d","4eb88310d6b4ed95c6d66a395b3d3cf559b85faec8f7691dafd405a92e055d6d","84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240","32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245","5195320c049ccff15766e070413bbec1c021bca03ee022838724a8ffb680bf3a","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24","febbaba219357c6c64adfa2e01789f274aa60e90c289938bfc80dd91facb2899","aff9a9f017f32b2e8b60754a4102db9d9cf9ff2b967804b50e070780aa45c9a8","7ecd3fe6353ec4c53672793e81445c2a319ccf0a298a91d77adcfa386b52f30d","6f0ec447e0da5ad4b9a3a2aef3e56b24601ca2b46ad7b23381d1941002923274","978c8f26ea9b3c58bfd4c8ddfde83741a6c2496fab72774109fe46819ca49708","432df97695aa47ebbed1c4a718632bf241ed85fad4d655bfdaca3316dbdb1509","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24","9ed60990ea290a2098ce65f3f019d7728ec3d500fbb05753ea3f4b9141da2f7d","7fa56f5d6962ab1e3cd424e758c3002b8665f7b0d8dcee9fe9e288d7751ac194"]
        NRSheetNavigationStack {
            AddContactsToListSheet(preSelectedContactPubkeys: suggestedPubkeys, theme: Themes.default.theme)
        }
    }
}



struct AddContactsToListInfo: Identifiable {
    let id = UUID()
    let pubkeys: Set<String>
}
