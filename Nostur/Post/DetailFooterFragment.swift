//
//  DetailFooterFragment.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/06/2023.
//

import SwiftUI
import NavigationBackport

struct DetailFooterFragment: View {
    @Environment(\.nxViewingContext) private var viewingContext
    private var nrPost: NRPost
    @ObservedObject private var footerAttributes: FooterAttributes
    
    init(nrPost: NRPost) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
    }
    
    @State var tallyString: String = ""
    
    var body: some View {
        Divider()
        if !viewingContext.contains(.preview) {
            TopZaps(id: nrPost.id)
        }
        HStack {
            NBNavigationLink(value: ViewPath.PostReactions(eventId: nrPost.id)) {
                HStack(spacing: 3) {
                    AnimatedNumber(number: footerAttributes.likesCount)
                    Text("reactions", comment: "Label for reactions count, example: (7) reactions")
                }
                .lineLimit(1)
            }
            NBNavigationLink(value: ViewPath.PostReposts(id: nrPost.id)) {
                HStack(spacing: 3) {
                    AnimatedNumber(number: footerAttributes.repostsCount)
                    Text("reposts", comment: "Label for reposts count, example: (7) reposts")
                }
                .lineLimit(1)
            }
            NBNavigationLink(value: ViewPath.PostZaps(nrPost: nrPost)) {
                HStack(spacing: 3) {
                    AnimatedNumber(number: footerAttributes.zapsCount)
                    Text("zaps", comment: "Label for zaps count, example: (4) zaps")
                        .layoutPriority(3)
                    
                    AnimatedNumberString(number: tallyString)
                        .opacity(footerAttributes.zapTally != 0 ? 1.0 : 0)
                        .layoutPriority(4)
                }
                .lineLimit(1)
            }
            
            Spacer()
            
            Text(nrPost.createdAt.formatted())
                .lineLimit(1)
                .layoutPriority(5)
        }
        .onAppear {
            guard !viewingContext.contains(.preview) else { return }
            loadTally(footerAttributes.zapTally)
        }
        .onChange(of: footerAttributes.zapTally) { [oldTally = footerAttributes.zapTally] newTally in
            guard newTally != oldTally, newTally > 0 else { return }
            Task { @MainActor in
                loadTally(newTally)
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(.gray)
        .font(.system(size: 14))
        .task { [weak nrPost] in
            guard let nrPost else { return }
            guard !viewingContext.contains(.preview) else { return }
            guard nrPost.contact.anyLud else { return }
            guard nrPost.contact.zapperPubkeys.isEmpty else {
                reverifyZaps(eventId: nrPost.id, expectedZpks: nrPost.contact.zapperPubkeys)
                return
            }
            do {
                if let lud16 = nrPost.contact.lud16, lud16 != "" {
                    let response = try await LUD16.getCallbackUrl(lud16: lud16)
                    await MainActor.run {
                        if (response.allowsNostr ?? false), let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
                            nrPost.contact.zapperPubkeys.insert(zapperPubkey)
#if DEBUG
                            L.og.debug("⚡️ contact.zapperPubkey updated: \(zapperPubkey)")
#endif
                            reverifyZaps(eventId: nrPost.id, expectedZpks: nrPost.contact.zapperPubkeys)
                        }
                    }
                }
                else if let lud06 = nrPost.contact.lud06, lud06 != "" {
                    let response = try await LUD16.getCallbackUrl(lud06: lud06)
                    await MainActor.run {
                        if (response.allowsNostr ?? false), let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
                            nrPost.contact.zapperPubkeys.insert(zapperPubkey)
#if DEBUG
                            L.og.debug("⚡️ contact.zapperPubkey updated: \(zapperPubkey)")
#endif
                            reverifyZaps(eventId: nrPost.id, expectedZpks: nrPost.contact.zapperPubkeys)
                        }
                    }
                }
            }
            catch {
#if DEBUG
                L.og.error("problem in lnurlp \(error)")
#endif
            }
        }
        Divider()
    }
    
    private func loadTally(_ tally: Int64) {
        if (ExchangeRateModel.shared.bitcoinPrice != 0.0) {
            let fiatPrice = String(format: "$%.02f",(Double(tally) / 100000000 * Double(ExchangeRateModel.shared.bitcoinPrice)))
            guard fiatPrice != tallyString else { return }
            tallyString = fiatPrice
        }
        else {
            guard String(tally.formatNumber) != tallyString else { return }
            tallyString = String(tally.formatNumber)
        }
    }
}

func reverifyZaps(eventId: String, expectedZpks: Set<String>) {
    bg().perform {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "zappedEventId == %@ AND kind == 9735", eventId)
        guard let zaps = try? bg().fetch(fr) else { return }
        for zap in zaps {
            if zap.flags != "zpk_verified" && expectedZpks.contains(zap.pubkey) {
                zap.flags = "zpk_verified"
            }
        }
        DataProvider.shared().saveToDiskNow(.bgContext)
    }
}


struct Previews_DetailFooterFragment_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadPosts() }) {
            if let p = PreviewFetcher.fetchNRPost() {
                DetailFooterFragment(nrPost: p)
            }
        }
    }
}
