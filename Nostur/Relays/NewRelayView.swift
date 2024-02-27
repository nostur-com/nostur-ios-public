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
    
    var onAdd: ((_ url: String) -> Void)? = nil
    
    var body: some View {
        
        NBNavigationStack {
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
                        if (onAdd != nil) {
                            onAdd!(url)
                        }
                        dismiss()
                    }
                }
            }
        }
        .nbUseNavigationStack(.never)
    }
}

struct NewRelayView_Previews: PreviewProvider {
    static var previews: some View {
        NewRelayView()
            .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
            .environmentObject(Themes.default)
    }
}
