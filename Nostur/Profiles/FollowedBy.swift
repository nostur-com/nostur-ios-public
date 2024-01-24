//
//  FollowedBy.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/11/2023.
//

import SwiftUI
import Collections

struct FollowedBy: View {
    
    public var pubkey:Pubkey? = nil
    public var alignment: HorizontalAlignment = .leading
    
    @State private var commonFollowerPFPs:[(Pubkey, URL)] = []
    
    private var firstRow:ArraySlice<(Pubkey, URL)> {
        commonFollowerPFPs.prefix(15)
    }
    
    private var secondRow:ArraySlice<(Pubkey, URL)> {
        commonFollowerPFPs.dropFirst(15).prefix(15)
    }
    
    var body: some View {
        VStack(alignment: alignment) {
            if !commonFollowerPFPs.isEmpty {
                Text("Followers you know").font(.caption)
                HStack(spacing: 2) {
                    ForEach(firstRow.indices, id:\.self) { index in
                        MiniPFP(pictureUrl: commonFollowerPFPs[index].1)
                            .onTapGesture {
                                navigateTo(ContactPath(key: commonFollowerPFPs[index].0))
                            }
                            .id(index)
                    }
                }
                
                HStack(spacing: 2) {
                    ForEach(secondRow.indices, id:\.self) { index in
                        MiniPFP(pictureUrl: commonFollowerPFPs[index].1)
                            .onTapGesture {
                                navigateTo(ContactPath(key: commonFollowerPFPs[index].0))
                            }
                            .id(index)
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
            guard let pubkey else { return }
            commonFollowerPFPs = commonFollowers(for: pubkey).compactMap({ pubkey in
                if let url = followingPFP(pubkey) {
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
//    FollowedBy()
//}
