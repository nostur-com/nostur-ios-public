//
//  OwnPostFooter.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/09/2023.
//

import SwiftUI
import Combine
// .relays
// .cancellationId
// .flags
// .sendNow()
// .unpublish()
// .isScreenshot

class OwnPostAttributes: ObservableObject {
    private let id: String
    var isOwnPost = false // all own accounts, so can undo from quick account switch post too
    @Published var relays: Set<String> = []
    var relaysCount: Int { relays.count }
    @Published var cancellationId: UUID? = nil
    @Published var flags = ""
    
    private var subscriptions = Set<AnyCancellable>()
    
    init(id: String, isOwnPost: Bool = false, relays: String = "", cancellationId: UUID? = nil, flags: String = "") {
        self.id = id
        self.isOwnPost = isOwnPost
        self.relays = relays.isEmpty ? [] : Set(relays.components(separatedBy: " "))
        self.cancellationId = cancellationId
        self.flags = flags
        self.setupListeners()
    }
    
    // If true, still time to Undo
    var isGoingToSend: Bool {
        relaysCount == 0 && (cancellationId != nil || flags == "nsecbunker_unsigned" || flags == "awaiting_send")
    }
    
    func setupListeners() {
        let id = self.id
        ViewUpdates.shared.eventStatChanged
            .filter { $0.id == id }
            .sink { [weak self] change in
                guard let self, let detectedRelay = change.detectedRelay else { return }
                if !self.relays.contains(detectedRelay) {
                    DispatchQueue.main.async { [weak self] in
                        self?.relays.insert(detectedRelay)
                    }
                }
            }
            .store(in: &subscriptions)
    }
}

struct OwnPostFooter: View {

    let nrPost: NRPost
    @ObservedObject var own: OwnPostAttributes
    @State private var unpublishing = false
    private var theme: Theme
    
    init(nrPost: NRPost, theme: Theme) {
        self.nrPost = nrPost
        self.own = nrPost.ownPostAttributes
        self.theme = theme
    }
    
    var body: some View {
        if (own.isOwnPost) {
            if (own.isGoingToSend) {
                HStack {
                    if own.flags == "nsecbunker_unsigned" {
                        Text("**Signing post...**")
                    }
                    else {
                        Text("**Sending post...**")
                    }
                    Spacer()
                    if own.flags != "nsecbunker_unsigned" {
                        Button("**Send now**") {
                            nrPost.sendNow()
                            DispatchQueue.main.async {
                                Drafts.shared.draft = ""
                                Drafts.shared.restoreDraft = ""
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(theme.accent)
                        .opacity(own.flags == "nsecbunker_unsigned" ? 0 : 1.0)
                        .padding(.trailing, 5)
                    }
                    if unpublishing {
                        Image(systemName:"hourglass.tophalf.filled")
                    }
                    else {
                        Button("Undo") {
                            unpublishing = true
                            nrPost.unpublish()
                            DispatchQueue.main.async {
                                Drafts.shared.draft = Drafts.shared.restoreDraft
                                Drafts.shared.restoreDraft = ""
                            }
                            
                        }
                        .buttonStyle(NRButtonStyle(theme: theme, style: .borderedProminent))
                        .foregroundColor(Color.white)
                        .opacity(own.flags == "nsecbunker_unsigned" ? 0 : 1.0)
                    }
                }
                .padding(.bottom, 5)
                .foregroundColor(Color.primary)
            }
            else if !nrPost.isScreenshot && !["awaiting_send","nsecbunker_unsigned","draft"].contains(own.flags) {
                HStack {
                    if own.flags == "nsecbunker_unsigned" && own.relaysCount != 0 {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                    }
                    else if own.relaysCount == 0 {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                    }
                    Text("Sent to \(own.relaysCount) relays", comment:"Message shown in footer of sent post")
                    Spacer()
                }
                .padding(.bottom, 5)
            }
        }
        else {
            EmptyView()
        }
    }
}

struct OwnPostFooter_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadPosts() }){
            if let p = PreviewFetcher.fetchNRPost() {
                OwnPostFooter(nrPost: p, theme: Themes.default.theme)
            }
        }
    }
}
