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
    @EnvironmentObject private var themes: Themes
    
    @ObservedObject private var settings: SettingsStore = .shared
    @State var newServerSheet = false
    
    @State private var serverList: [String] = []
    
    var body: some View {
        Form {
            Section {
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
                
                Button("Add blossom server") {
                    newServerSheet = true
                }
            } footer: {
                if serverList.count > 1 {
                    Text("Servers higher on the list will be used first")
                }
            }
            .listRowBackground(themes.theme.listBackground)
        }
        .scrollContentBackgroundCompat(.hidden)
        .background(themes.theme.background)
        .toolbar {
            
            ToolbarItem(placement: .navigationBarTrailing) {
                if !serverList.isEmpty {
                    EditButton()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    SettingsStore.shared.blossomServerList = serverList
                    dismiss()
                }) {
                    Text("Done")
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
                    .environmentObject(themes)
            }
            .presentationBackgroundCompat(themes.theme.listBackground)
        }
        .onAppear {
            serverList = SettingsStore.shared.blossomServerList
            if serverList.isEmpty {
                newServerSheet = true
            }
        }
        .onDisappear {
            SettingsStore.shared.blossomServerList = serverList 
        }
    }
}

#Preview("Blossom server list") {
    NBNavigationStack {
        BlossomServerList()
    }
    .environmentObject(Themes.default)
}
