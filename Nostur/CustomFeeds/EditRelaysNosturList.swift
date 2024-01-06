//
//  EditList.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/04/2023.
//

import SwiftUI
import NavigationBackport

struct EditRelaysNosturList: View {
    
    let list:CloudFeed
    @Environment(\.dismiss) var dismiss
    
    @State var title = ""
    @State var wotEnabled = true
    @State var selectedRelays:Set<CloudRelay> = []
    
    private var selectedRelaysData:Set<RelayData> {
        Set(selectedRelays.map { $0.toStruct() })
    }
    
    @State var showAsTab = true
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\CloudRelay.createdAt_, order: .forward)],
        animation: .default)
    var relays: FetchedResults<CloudRelay>
    
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
            
            Toggle(isOn: $showAsTab, label: { Text("Pin on tab bar", comment: "Toggle to pin/unpin a feed on tab bar")})
            
            Section(header: Text("Relay selection", comment: "Header for a feed setting")) {
                ForEach(relays, id:\.objectID) { relay in
                        HStack {
                            Image(systemName: selectedRelays.contains(relay) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedRelays.contains(relay) ? Color.primary : Color.secondary)
                            Text(relay.url_ ?? "(Missing relay address)")
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
            showAsTab = list.showAsTab
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    list.name = title
                    list.relays_ = selectedRelays
                    list.wotEnabled = wotEnabled
                    list.showAsTab = showAsTab
                    DataProvider.shared().save()
                    dismiss()
                    sendNotification(.listRelaysChanged, NewRelaysForList(subscriptionId: list.subscriptionId, relays: selectedRelaysData, wotEnabled: wotEnabled))
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
//            pe.loadRelayNosturLists()
        }) {
            NBNavigationStack {
                if let list = PreviewFetcher.fetchList() {
                    EditRelaysNosturList(list: list)
                    .withNavigationDestinations()
                }
            }
        }
    }
}
