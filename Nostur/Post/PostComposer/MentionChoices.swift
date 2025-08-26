//
//  MentionChoices.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/10/2023.
//

import SwiftUI

struct MentionChoices: View {
    @ObservedObject var vm: NewPostModel
    
    var body: some View {
        if vm.showMentioning {
            VStack(spacing: 0) {
                HStack {
                    Text("Choose to tag:")
                        .font(.caption)
                    Spacer()
                    Button("Cancel") {
                        vm.showMentioning = false
                    }
                }
                .padding(10)
                ScrollView {
                    LazyVStack {
                        ForEach(vm.filteredContactSearchResults) { nrContact in
                            NRContactSearchResultRow(nrContact: nrContact, onSelect: {
                                vm.selectContactSearchResult(nrContact)
                            })
                            HStack {
                                Spacer()
                                LazyFollowedBy(pubkey: nrContact.pubkey, alignment: .trailing, minimal: true)
                            }
                            Divider()
                        }
                    }
                }
                .padding([.top,.leading,.trailing])
            }
        }
    }
}


struct LazyFollowedBy: View {
    
    public var pubkey: Pubkey? = nil
    public var alignment: HorizontalAlignment = .leading
    public var minimal: Bool = false
    
    @State private var didLoad = false
    @State private var timer: Timer?
    
    var body: some View {
        VStack {
            if didLoad {
                FollowedBy(pubkey: pubkey, alignment: alignment, minimal: minimal)
            }
            else {
                EmptyView()
            }
        }
        .onAppear {
            guard !didLoad else { return }
            self.load()
        }
        .onDisappear {
            self.cancel()
        }
    }
    
    private func load() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            withAnimation {
                didLoad = true
            }
        }
    }
    
    private func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
