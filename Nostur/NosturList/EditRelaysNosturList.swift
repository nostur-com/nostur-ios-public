//
//  EditList.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/04/2023.
//

import SwiftUI

struct EditRelaysNosturList: View {
    
    let list:NosturList
    @Environment(\.dismiss) var dismiss
    
    @State var title = ""
    @State var wotEnabled = true
    @State var selectedRelays:Set<Relay> = []
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Relay.createdAt, order: .forward)],
        animation: .default)
    var relays: FetchedResults<Relay>
    
    var formIsValid:Bool {
        guard !title.isEmpty else { return false }
        guard !selectedRelays.isEmpty else { return false }
        return true
    }
    
    var body: some View {
        List {
            Section(header: Text("Title", comment: "Header for entering title of a feed")) {
                TextField(String(localized:"Title of your feed", comment:"Placeholder for input field to enter title of a List"), text: $title)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            
            Section(header: Text("Relay selection", comment: "Header for a feed setting")) {
                ForEach(relays, id:\.objectID) { relay in
                        HStack {
                            Image(systemName: selectedRelays.contains(relay) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedRelays.contains(relay) ? Color.primary : Color.secondary)
                            Text(relay.url ?? "(Missing relay address)")
                        }
                        .id(relay.objectID)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedRelays.contains(relay) {
                                selectedRelays.remove(relay)
                            }
                            else {
                                selectedRelays.insert(relay)
                            }
                        }
                    }
            }
            
            Section(header: Text("Spam filter", comment: "Header for a feed setting")) {
                Toggle(isOn: $wotEnabled) {
                    Text("Enable Web of Trust filter")
                    Text("Only show content from your follows or follows-follows")
                }
            }
        }
        .navigationTitle("Edit relays feed")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            title = list.name ?? ""
            selectedRelays = list.relays_
            wotEnabled = list.wotEnabled
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    list.name = title
                    list.relays = selectedRelays
                    list.wotEnabled = wotEnabled
                    DataProvider.shared().save()
                    dismiss()
                    sendNotification(.listRelaysChanged, NewRelaysForList(subscriptionId: list.subscriptionId, relays: selectedRelays, wotEnabled: wotEnabled))
                }
                .disabled(!formIsValid)
            }
        }
    }
}

struct EditRelaysList_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadRelays()
            pe.loadRelayNosturLists()
        }) {
            NavigationStack {
                if let list = PreviewFetcher.fetchList() {
                    EditRelaysNosturList(list: list)
                    .withNavigationDestinations()
                }
            }
        }
    }
}
