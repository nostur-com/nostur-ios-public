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
                        ForEach(vm.filteredContactSearchResults) { contact in
                            ContactSearchResultRow(contact: contact, onSelect: {
                                vm.selectContactSearchResult(contact)
                            })
                            Divider()
                        }
                    }
                }
                .padding([.top,.leading,.trailing])
            }
        }
    }
}
