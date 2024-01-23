//
//  DetailFooterFragment.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/06/2023.
//

import SwiftUI
import NavigationBackport

struct DetailFooterFragment: View {
    private var nrPost: NRPost
    @ObservedObject private var footerAttributes: FooterAttributes
    
    init(nrPost: NRPost) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
    }
    
    @State var tallyString:String = ""
    
    var body: some View {
        Divider()
        HStack {
            NBNavigationLink(value: ViewPath.NoteReactions(id: nrPost.id)) {
                HStack(spacing: 3) {
                    AnimatedNumber(number: footerAttributes.likesCount)
//                        .fontWeight(.bold)
                    Text("reactions", comment: "Label for reactions count, example: (7) reactions")
                }
            }
            NBNavigationLink(value: ViewPath.NoteReposts(id: nrPost.id)) {
                HStack(spacing: 3) {
                    AnimatedNumber(number: footerAttributes.repostsCount)
//                        .fontWeight(.bold)
                    Text("reposts", comment: "Label for reposts count, example: (7) reposts")
                }
            }
            NBNavigationLink(value: ViewPath.NoteZaps(id: nrPost.id)) {
                HStack(spacing: 3) {
                    AnimatedNumber(number: footerAttributes.zapsCount)
//                        .fontWeight(.bold)
                    Text("zaps", comment: "Label for zaps count, example: (4) zaps")
                    
                    AnimatedNumberString(number: tallyString)
//                        .fontWeight(.bold)
                        .opacity(footerAttributes.zapTally != 0 ? 1.0 : 0)
                }
            }
            
            Spacer()
            
            Text(nrPost.createdAt.formatted(date: .omitted, time: .shortened))
            Text(nrPost.createdAt.formatted(
                .dateTime
                    .day().month(.defaultDigits)
            ))
        }
        .onAppear {
            loadTally(footerAttributes.zapTally)
        }
        .onChange(of: footerAttributes.zapTally) { newTally in
            loadTally(newTally)
        }
        .buttonStyle(.plain)
        .foregroundColor(.gray)
        .font(.system(size: 14))
        .task { [weak nrPost] in
            guard let nrPost else { return }
            guard let contact = nrPost.contact?.mainContact else { return }
            guard contact.anyLud else { return }
            guard contact.zapperPubkey == nil else {
                if let zpk = nrPost.contact?.mainContact?.zapperPubkey {
                    reverifyZaps(eventId: nrPost.id, expectedZpk: zpk)
                }
                return
            }
            do {
                if let lud16 = contact.lud16, lud16 != "" {
                    let response = try await LUD16.getCallbackUrl(lud16: lud16)
                    await MainActor.run {
                        if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                            contact.zapperPubkey = response.nostrPubkey!
                            L.og.info("contact.zapperPubkey updated: \(response.nostrPubkey!)")
                            reverifyZaps(eventId: nrPost.id, expectedZpk: contact.zapperPubkey!)
                        }
                    }
                }
                else if let lud06 = contact.lud06, lud06 != "" {
                    let response = try await LUD16.getCallbackUrl(lud06: lud06)
                    await MainActor.run {
                        if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                            contact.zapperPubkey = response.nostrPubkey!
                            L.og.info("contact.zapperPubkey updated: \(response.nostrPubkey!)")
                            reverifyZaps(eventId: nrPost.id, expectedZpk: contact.zapperPubkey!)
                        }
                    }
                }
            }
            catch {
                L.og.error("problem in lnurlp \(error)")
            }
        }
        Divider()
    }
    
    private func loadTally(_ tally:Int64) {
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

func reverifyZaps(eventId: String, expectedZpk: String) {
    bg().perform {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "zappedEventId == %@ AND kind == 9735", eventId)
        guard let zaps = try? bg().fetch(fr) else { return }
        for zap in zaps {
            if zap.flags != "zpk_verified" && zap.pubkey == expectedZpk {
                zap.flags = "zpk_verified"
            }
        }
        bgSave()
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
