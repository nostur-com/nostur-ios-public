//
//  AddBlossomServerSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/05/2025.
//

import SwiftUI
import NostrEssentials
import NavigationBackport

struct AddBlossomServerSheet: View {
    @EnvironmentObject private var themes: Themes
    @Environment(\.dismiss) private var dismiss
    
    @State private var server = ""
    @State private var error: String?
    @State private var checking = false
    
    public var onAdd: ((String) -> Void)
    
    var body: some View {
        List {
            Section {
                TextField(String(localized:"Server address", comment:"Placeholder for input field to enter blossom server address"), text: $server)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            } header: { Text("Blossom server", comment: "Header for entering blossom server address") } footer: {
                if let error {
                    Text(error)
                        .fontWeightBold()
                        .foregroundColor(Color.red)
                }
            }
            .listRowBackground(themes.theme.background)
        }
        .scrollContentBackgroundCompat(.hidden)
        .background(themes.theme.listBackground)
        .navigationTitle(String(localized:"Add blossom server", comment:"Navigation title for screen to create a new feed"))
        .navigationBarTitleDisplayMode(.inline)
        
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if checking {
                    ProgressView()
                }
                else {
                    Button("Add") {
                        if let urlObj = URL(string: server),
                           let components = URLComponents(url: urlObj, resolvingAgainstBaseURL: false),
                           let host = components.host
                        {

                            if let scheme = components.scheme {
                                server = "\(scheme)://\(host)"
                                
                                if let port = components.port, port != 443 {
                                    server = "\(server):\(port)"
                                }
                            }
                            else {
                                server = "https://\(host)"
                                
                                if let port = components.port, port != 443 {
                                    server = "\(server):\(port)"
                                }
                            }
                        }
                        else {
                            server = "https://\(server)"
                        }
                        
                        Task {
                            await checkBlossomServer()
                        }
                    }
                }
            }
        }
    }
    
    func checkBlossomServer() async {
        
        // Use account key
        let keys = if let account = account(), isFullAccount(account), let pk = account.privateKey {
            try? NostrEssentials.Keys(privateKeyHex: pk)
        }
        else { // Try with dummy key
            try? NostrEssentials.Keys.newKeys()
        }
        error = nil
        checking = true

        // Test media server using HEAD /media
        guard let keys else {
            checking = false
            return
        }
        let testSuccess = (try? await NostrEssentials.testBlossomServer(URL(string: server)!, keys: keys)) ?? false
        
        if testSuccess {
            onAdd(server)
            dismiss()
            error = nil
        }
        else {
            error = "Server not supported."
        }
        
        checking = false
    }
}


#Preview("Add server sheet") {
    NBNavigationStack {
        AddBlossomServerSheet { newServerUrlString in
            print(newServerUrlString)
        }
    }
    .environmentObject(Themes.default)
}
