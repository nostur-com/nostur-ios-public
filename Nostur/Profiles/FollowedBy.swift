//
//  FollowedBy.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/11/2023.
//

import SwiftUI

struct FollowedBy: View {
    
    public var pubkey: Pubkey? = nil
    public var alignment: HorizontalAlignment = .leading
    public var minimal: Bool = false
    public var showZero: Bool = false
    
    @State private var commonFollowerPFPs: [(Pubkey, URL)] = []
    
    private var firstRow: ArraySlice<(Pubkey, URL)> {
        commonFollowerPFPs.prefix(15)
    }
    
    private var secondRow: ArraySlice<(Pubkey, URL)> {
        commonFollowerPFPs.dropFirst(15).prefix(15)
    }
    
    var body: some View {
        VStack(alignment: alignment) {
            Color.clear
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            if !commonFollowerPFPs.isEmpty || showZero {
                if !minimal {
                    if commonFollowerPFPs.isEmpty {
                        Text("Followed by 0 others you follow").font(.caption)
                    }
                    else {
                        Text("Followed by").font(.caption)
                    }
                }
                HStack(spacing: 2) {
                    ForEach(firstRow.indices, id:\.self) { index in
                        MiniPFP(pictureUrl: commonFollowerPFPs[index].1)
                            .onTapGesture {
                                navigateTo(ContactPath(key: commonFollowerPFPs[index].0))
                            }
                            .id(index)
                    }
                }
                
                if !minimal {
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
            }
            if minimal && commonFollowerPFPs.count > 16 {
                Text("+\(commonFollowerPFPs.count - 15) others").font(.caption)
            }
            else if commonFollowerPFPs.count > 31 {
                Text("and \(commonFollowerPFPs.count - 30) others you follow").font(.caption)
            }
            else if commonFollowerPFPs.count > 30 {
                Text("and 1 other person you follow").font(.caption)
            }
        }
        .task {
            guard let pubkey, let followingCache = NRState.shared.loggedInAccount?.followingCache else { return }
            
            bg().perform {
                let commonFollowerPubkeys = commonFollowers(for: pubkey)
                let commonFollowerPFPs = commonFollowerPubkeys.compactMap({ pubkey in
                    if let url = followingCache[pubkey]?.pfpURL {
                        return (pubkey, url)
                    }
                    return nil
                })
               
                DispatchQueue.main.async {
                    withAnimation {
                        self.commonFollowerPFPs = commonFollowerPFPs
                    }
                }
            }
            
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
