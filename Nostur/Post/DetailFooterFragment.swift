import SwiftUI

struct DetailFooterFragment: View {
    let er:ExchangeRateModel = .shared // Not Observed for performance
    @ObservedObject var nrPost:NRPost
    
    var tallyString:String {
        if (er.bitcoinPrice != 0.0) {
            let fiatPrice = String(format: "$%.02f",(Double(nrPost.zapTally) / 100000000 * Double(er.bitcoinPrice)))
            return fiatPrice
        }
        return String(nrPost.zapTally.formatNumber)
    }

    var body: some View {
        Divider()
        HStack(spacing: 20) {
            NavigationLink(value: ViewPath.NoteReactions(id: nrPost.id)) {
                HStack(spacing:5) {
                    AnimatedNumber(number: nrPost.likesCount)
                        .fontWeight(.bold)
                    Text("reactions", comment: "Label for reactions count, example: (7) reactions")
                }
            }
            NavigationLink(value: ViewPath.NoteZaps(id: nrPost.id)) {
                HStack(spacing:5) {
                    AnimatedNumber(number: nrPost.zapsCount)
                        .fontWeight(.bold)
                    Text("zaps", comment: "Label for zaps count, example: (4) zaps")
                }
                
                if IS_APPLE_TYRANNY {
                    HStack(spacing:5) {
                        AnimatedNumberString(number: tallyString)
                            .fontWeight(.bold)
                        //                    Text("zaps", comment: "Label for zaps count, example: (4) zaps")
                    }
                    .opacity(nrPost.zapTally != 0 ? 1.0 : 0)
                }
            }
            
            Spacer()
            
            Text("\(nrPost.createdAt.formatted(date: .omitted, time: .shortened)) · \(nrPost.createdAt.formatted(date: .numeric, time: .omitted))")
        }
        .foregroundColor(.gray)
        .padding(.vertical, 10)
        .padding(.trailing, 10)
        .font(.system(size: 14))
        Divider()
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
