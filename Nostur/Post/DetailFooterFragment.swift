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
        VStack(spacing: 5) {
            HStack(spacing: 2) {
                NBNavigationLink(value: ViewPath.PostReactions(eventId: nrPost.id)) {
                    HStack(spacing: 2) {
                        AnimatedNumber(number: footerAttributes.likesCount)
                            .layoutPriority(footerAttributes.likesCount == 0 ? -1 : 1)
                        Text("reactions", comment: "Label for reactions count, example: (7) reactions")
                            .layoutPriority(footerAttributes.likesCount == 0 ? -1 : 1)
                    }
                    .lineLimit(1)
                }
                Spacer()
                NBNavigationLink(value: ViewPath.PostReposts(id: nrPost.id)) {
                    HStack(spacing: 2) {
                        AnimatedNumber(number: footerAttributes.repostsCount)
                            .layoutPriority(footerAttributes.repostsCount == 0 ? -1 : 2)
                        Text("reposts", comment: "Label for reposts count, example: (7) reposts")
                            .layoutPriority(footerAttributes.repostsCount == 0 ? -1 : 2)
                    }
                    .lineLimit(1)
                }
                Spacer()
                NBNavigationLink(value: ViewPath.PostMentions(id: nrPost.id)) {
                    HStack(spacing: 2) {
                        AnimatedNumber(number: footerAttributes.mentionsCount)
                            .layoutPriority(footerAttributes.mentionsCount == 0 ? -1 : 2)
                        Text("mentions", comment: "Label for quoted count, example: (7) quoted")
                            .layoutPriority(footerAttributes.mentionsCount == 0 ? -1 : 2)
                    }
                    .lineLimit(1)
                }
                Spacer()
                NBNavigationLink(value: ViewPath.PostZaps(nrPost: nrPost)) {
                    HStack(spacing: 2) {
                        AnimatedNumber(number: footerAttributes.zapsCount)
                            .layoutPriority(footerAttributes.zapsCount == 0 ? -1 : 3)
                        Text("zaps", comment: "Label for zaps count, example: (4) zaps")
                            .layoutPriority(footerAttributes.zapsCount == 0 ? -1 : 3)
                        
                        if footerAttributes.zapsCount != 0 {
                            Text(tallyString)
                                .opacity(tallyString != "" ? 1.0 : 0)
                                .layoutPriority(tallyString == "" ? -1 : 3)
                        }
                    }
                    .lineLimit(1)
                }
            }
        }
        .onAppear {
            guard !viewingContext.contains(.preview) else { return }
            if SettingsStore.shared.showFiat {
                loadTally(footerAttributes.zapTally)
            }
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
                        if let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
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
                        if let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
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
            tallyString = "\(String(tally.formatNumber)) sats"
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
        PreviewContainer {
            DetailFooterFragment(nrPost: testNRPost())
        }
        .frame(width: 350)
    }
}
