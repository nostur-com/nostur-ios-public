//
//  NewRelayView.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/01/2023.
//

import SwiftUI

struct NewRelayView: View {
//    @EnvironmentObject var theme:Theme
    @Environment(\.dismiss) private var dismiss
    @State var url = "wss://"
    
    var onAdd:((_ url:String) -> Void)? = nil
    
    var body: some View {
        
        NavigationStack {
//            VStack {
                Form {
                    TextField("wss://relay...", text: $url)
                        .keyboardType(.URL)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                }
//            }
//            .padding()
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
    }
}

struct NewRelayView_Previews: PreviewProvider {
    static var previews: some View {
        NewRelayView()
            .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
            .environmentObject(Theme.default)
    }
}
