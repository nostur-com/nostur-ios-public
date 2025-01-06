//
//  NewRelayView.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/01/2023.
//

import SwiftUI
import NavigationBackport

struct NewRelayView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url = "wss://"
    
    var body: some View {
        Form {
            TextField("wss://relay...", text: $url)
                .keyboardType(.URL)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
        }
        .navigationTitle(String(localized:"Add relay", comment:"Navigation title for Add relay screen"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add") {
                    add()
                }
            }
        }
    }
    
    @MainActor
    func add() {
        dismiss()
        let relay = CloudRelay(context: viewContext())
        relay.createdAt = Date()
        relay.url_ = url
        
        do {
            try viewContext().save()
            L.og.debug("💾💾💾💾 Saved to disk / iCloud 💾💾💾💾")
            if (relay.read || relay.write) {
                ConnectionPool.shared.addConnection(relay.toStruct())
            }
        } catch {
            L.og.error("Unresolved error \(error)")
        }
    }
}

struct NewRelayView_Previews: PreviewProvider {
    static var previews: some View {
        NBNavigationStack {
            NewRelayView()
                .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
                .environmentObject(Themes.default)
        }
    }
}
