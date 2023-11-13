//
//  FollowedBy.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/11/2023.
//

import SwiftUI
import Collections

struct FollowedBy: View {
    public var pubkey:Pubkey
    
    @State private var commonFollowerPFPs:[(Pubkey, URL)] = []
    
    private var firstRow:ArraySlice<(Pubkey, URL)> {
        commonFollowerPFPs.prefix(15)
    }
    
    private var secondRow:ArraySlice<(Pubkey, URL)> {
        commonFollowerPFPs.dropFirst(15).prefix(15)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            if !commonFollowerPFPs.isEmpty {
                Text("Followed by").font(.caption)
                ZStack(alignment:.leading) {
                    ForEach(firstRow.indices, id:\.self) { index in
                        MiniPFP(pictureUrl: commonFollowerPFPs[index].1)
                            .onTapGesture {
                                navigateTo(ContactPath(key: commonFollowerPFPs[index].0))
                            }
                            .id(index)
                            .zIndex(-Double(index))
                            .offset(x:Double(0 + (22*index)))
                    }
                }
                
                ZStack(alignment:.leading) {
                    ForEach(secondRow.indices, id:\.self) { index in
                        MiniPFP(pictureUrl: commonFollowerPFPs[index].1)
                            .onTapGesture {
                                navigateTo(ContactPath(key: commonFollowerPFPs[index].0))
                            }
                            .id(index)
                            .zIndex(-Double(index))
                            .offset(x:Double(0 + (22*(index-15))))
                    }
                }
            }
            if commonFollowerPFPs.count > 31 {
                Text("and \(commonFollowerPFPs.count - 30) others you follow.").font(.caption)
            }
            else if commonFollowerPFPs.count > 30 {
                Text("and 1 other person you follow.").font(.caption)
            }
        }
        .task {
            guard let followingPFPs = NRState.shared.loggedInAccount?.followingPFPs else { return }
            commonFollowerPFPs = commonFollowers(for: pubkey).compactMap({ pubkey in
                if let url = followingPFPs[pubkey] {
                    return (pubkey, url)
                }
                return nil
            })
        }
    }
}

func commonFollowers(for pubkey: Pubkey) -> [Pubkey] {
    guard let account = account() else { return [] }
    let fr = Event.fetchRequest()
    fr.predicate = NSPredicate(format: "kind == 3 AND pubkey IN %@", account.followingPubkeys)
    guard let followingContactLists = try? context().fetch(fr) else { return [] }
    return followingContactLists
        .filter ({
            return $0.fastPs.contains(where: { pTuple in
                pTuple.1 == pubkey
            })
        })
        .compactMap({ $0.pubkey })
}



//#Preview {
//    FollowedBy(pubkey: )
//}
