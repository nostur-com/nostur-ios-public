//
//  PFPandName.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/08/2025.
//

import SwiftUI

// TODO: Should start reusing this everywhere? add flags and toggles for size / layout / position etc / in sheet or not (for dismiss)
struct PFPandName: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var nrContact: NRContact
    
    private var size: CGFloat
    private var alignment: HorizontalAlignment
    
    init(nrContact: NRContact, size: CGFloat = 20.0, alignment: HorizontalAlignment = .leading) {
        self.nrContact = nrContact
        self.size = size
        self.alignment = alignment
    }
    
    init(pubkey: String, size: CGFloat = 20.0, alignment: HorizontalAlignment = .leading) {
        self.nrContact = NRContact.instance(of: pubkey)
        self.size = size
        self.alignment = alignment
    }
    
    var body: some View {
        HStack {
            if alignment == .trailing {
                Spacer()
            }
            ObservedPFP(nrContact: nrContact, size: 20.0)
            Text(nrContact.anyName)
            if alignment == .leading {
                Spacer()
            }
        }
        .onAppear {
            bg().perform {
                if nrContact.metadata_created_at == 0 {
                    QueuedFetcher.shared.enqueue(pTag: nrContact.pubkey)
                }
            }
        }
        .onDisappear {
            bg().perform {
                if nrContact.metadata_created_at == 0 {
                    QueuedFetcher.shared.dequeue(pTag: nrContact.pubkey)
                }
            }
        }
    }
}

#Preview {
    PFPandName(pubkey: "")
}
