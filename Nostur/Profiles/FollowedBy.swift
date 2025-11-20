//
//  FollowedBy.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/11/2023.
//

import SwiftUI

let FOLLOWED_BY_MIN_HEIGHT = 24.0

struct FollowedBy: View {
    @Environment(\.containerID) private var containerID
    
    public var pubkey: Pubkey? = nil
    public var alignment: HorizontalAlignment = .leading
    public var minimal: Bool = false
    public var showZero: Bool = false
    public var showHeaderText: Bool = true
    
    @State private var commonFollowerPFPs: [(Pubkey, URL)] = []
    
    private var textAlignment: Alignment {
        if alignment == HorizontalAlignment.leading {
            return Alignment.leading
        }
        return Alignment.trailing
    }
    
    private var firstRow: ArraySlice<(Pubkey, URL)> {
        commonFollowerPFPs.prefix(15)
    }
    
    private var secondRow: ArraySlice<(Pubkey, URL)> {
        commonFollowerPFPs.dropFirst(15).prefix(15)
    }
    
    var body: some View {
        VStack(alignment: alignment) {
            if (!commonFollowerPFPs.isEmpty || showZero) {
                if !minimal && showHeaderText {
                    if commonFollowerPFPs.isEmpty {
                        Text("Followed by 0 others you follow").font(.caption)
                            .frame(maxWidth: .infinity, alignment: textAlignment)
                    }
                    else {
                        Text("Followed by").font(.caption)
                            .frame(maxWidth: .infinity, alignment: textAlignment)
                    }
                }
                HStack(spacing: 2) {
                    ForEach(firstRow.indices, id:\.self) { index in
                        MiniPFP(pictureUrl: commonFollowerPFPs[index].1)
                            .highPriorityGesture( // Unsure why first/left mini pfps are sometimes untappable with normal onTap
                                TapGesture()
                                    .onEnded { _ in
                                        navigateTo(ContactPath(key: commonFollowerPFPs[index].0), context: containerID)
                                    }
                            )
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: textAlignment)
                
                if !minimal {
                    HStack(spacing: 2) {
                        ForEach(secondRow.indices, id:\.self) { index in
                            MiniPFP(pictureUrl: commonFollowerPFPs[index].1)
                                .highPriorityGesture( // Unsure why first/left mini pfps are sometimes untappable with normal onTap
                                    TapGesture()
                                        .onEnded { _ in
                                            navigateTo(ContactPath(key: commonFollowerPFPs[index].0), context: containerID)
                                        }
                                )
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: textAlignment)
                }
            }
            if minimal && commonFollowerPFPs.count > 16 {
                Text("+\(commonFollowerPFPs.count - 15) others").font(.caption)
                    .frame(maxWidth: .infinity, alignment: textAlignment)
            }
            else if commonFollowerPFPs.count > 31 {
                Text("and \(commonFollowerPFPs.count - 30) others you follow").font(.caption)
                    .frame(maxWidth: .infinity, alignment: textAlignment)
            }
            else if commonFollowerPFPs.count > 30 {
                Text("and 1 other person you follow").font(.caption)
                    .frame(maxWidth: .infinity, alignment: textAlignment)
            }
        }
        .frame(minHeight: FOLLOWED_BY_MIN_HEIGHT)
        .frame(maxWidth: .infinity)
        .task {
            guard let pubkey, let followingCache = AccountsState.shared.loggedInAccount?.followingCache else { return }
            
            bg().perform {
                let commonFollowerPubkeys = Set(commonFollowers(for: pubkey))
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

struct LazyFollowedBy: View {
    
    public var pubkey: Pubkey? = nil
    public var alignment: HorizontalAlignment = .leading
    public var minimal: Bool = false
    
    @State private var didLoad = false
    @State private var timer: Timer?
    
    var body: some View {
        Container {
            if didLoad {
                FollowedBy(pubkey: pubkey, alignment: alignment, minimal: minimal)
            }
            else {
                Color.clear
                    .frame(height: FOLLOWED_BY_MIN_HEIGHT)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            self.load()
        }
        .onDisappear {
            self.cancel()
        }
    }
    
    private func load() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            withAnimation {
                didLoad = true
            }
        }
    }
    
    private func cancel() {
        timer?.invalidate()
        timer = nil
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
