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
                    HStack(spacing: 12) {
#if os(iOS) || targetEnvironment(macCatalyst)
                        Button {
                            hideKeyboard()
                        } label: {
                            Label("Hide keyboard", systemImage: "keyboard.chevron.compact.down")
                        }
                        .labelStyle(.iconOnly)
#endif
                        Button("Cancel", systemImage: "xmark") {
                            vm.showMentioning = false
                        }
                        .labelStyle(.iconOnly)
                    }
                    .font(.body)
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

    private func hideKeyboard() {
#if os(iOS) || targetEnvironment(macCatalyst)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }
}
