//
//  Nip96Configurator.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/10/2023.
//

import SwiftUI
import NostrEssentials
import Combine

struct Nip96Configurator: View {
    @AppStorage("nip96_api_url") private var nip96apiUrl = ""
    @EnvironmentObject private var themes:Themes
    @Environment(\.dismiss) private var dismiss
    @State private var state:ConfiguratorState = .initialized
    @State private var tosUrl:String?
    @State private var address = ""
    @State private var errorMessage = ""
    @State private var subscriptions = Set<AnyCancellable>()
    
    enum ConfiguratorState {
        case initialized
        case checking
        case success
        case fail
    }
    
    var body: some View {
        VStack {
            if (state == .success) {
                Text("File Storage server configured successfully!")
                    .multilineTextAlignment(.center)
                    .padding(10)
            }
            else {
                Text("Enter a NIP-96 compatible media server address to host your images")
                    .multilineTextAlignment(.center)
                    .padding(10)
                
            }
            
            if (state == .success) {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.green)
                    .frame(height: 75)
                    .onTapGesture {
                        dismiss()
                    }
                
                if let tosUrl = tosUrl {
                    Link("Terms of Service", destination: URL(string: tosUrl)!)
                        .padding()
                }
            }
            else {
                
                Text("File Storage Server address", comment: "File Storage Server address")
                    .fontWeight(.bold)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 20)
                
                TextField("", text: $address, prompt: Text(verbatim: "https://nostrcheck.me"))
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .padding(.top, 0)
                    .padding(.horizontal, 10)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage).fontWeight(.bold).foregroundColor(.red)
                }

                if state != .checking {
                    Button(String(localized:"Activate", comment: "Button to check if a file storage server is compatible")) { startCheck() }
                        .buttonStyle(NRButtonStyle(theme: themes.theme, style: .borderedProminent))
                        .disabled(!validUri)
                        .opacity(validUri ? 1.0 : 0.5)
                        .padding()
                }
                else {
                    ProgressView()
                        .padding()
                }
                
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle((String(localized:"Custom File Storage", comment:"Navigation title for setting up a custom File Storage Server")))
        .toolbar {
            if state == .success {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            else {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onReceive(receiveNotification(.nwcInfoReceived)) { notification in
            // Here we received the info event from the NWC relay
            
        }
    }
    
    func startCheck() {
        errorMessage = ""
        state = .checking
        // Allow pasting of just domain or full nip96.json path
        // Also handle pasted trailing slash
        var wellKnownAddress = (address.replacingOccurrences(of: "/.well-known/nostr/nip96.json", with: "") + "/.well-known/nostr/nip96.json").replacingOccurrences(of: "//.", with: "/.")
        
        if !wellKnownAddress.contains("://") {
            wellKnownAddress = ("https://" + wellKnownAddress)
        }
        
        guard let url = URL(string: wellKnownAddress) else { return }
        let request = URLRequest(url: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        URLSession.shared
            .dataTaskPublisher(for: request)
            .tryMap() { element -> Data in
                guard let httpResponse = element.response as? HTTPURLResponse,
                      httpResponse.statusCode == 200
                else { throw URLError(.badServerResponse) }
                return element.data
            }
            .decode(type: NIP96WellKnown.self, decoder: decoder)
            .tryMap { nip96wellKnown -> NIP96WellKnown in

//                print(nip96wellKnown)
                guard !nip96wellKnown.apiUrl.isEmpty && URL(string: nip96wellKnown.apiUrl) != nil
                else { throw URLError(.unknown) }
                
                nip96apiUrl = nip96wellKnown.apiUrl
                
                if let tosUrlString = nip96wellKnown.tosUrl, let tosUrl = URL(string: tosUrlString) {
                    self.tosUrl = tosUrl.absoluteString
                }
                state = .success
                return nip96wellKnown
            }
            .eraseToAnyPublisher()
            .sink(receiveCompletion: { completion in
                switch completion {
                case .finished:
                    L.og.debug("Finished")
                case .failure(_):
                    state = .fail
                    errorMessage = "Unable to connect"
                }
            }, receiveValue: { value in
                
            })
            .store(in: &subscriptions)
    }
    
    var validUri:Bool {
        if URL(string: address) != nil {
            return true
        }
        return false
    }
}

import NavigationBackport

#Preview {
    NBNavigationStack {
        Nip96Configurator()
    }
    .environmentObject(Themes.default)
}

