//
//  FetchingAnimationView.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/06/2025.
//

import SwiftUI

struct FetchingAnimationView: View {
    @EnvironmentObject private var la: LoggedInAccount
    @State private var noPFPs = false
    @State private var yesPFPs = false
    @State private var isAnimating = false
    @State private var pfpUrls: [URL] = []
    @State private var distances: [CGFloat] = (0..<10).map { _ in CGFloat.random(in: 80...120) }
    @State private var speeds: [Double] = (0..<10).map { _ in Double.random(in: 1.0...2.5) }
    
    var body: some View {
        Container {
            if noPFPs {
                CircleAnimationViews()
            }
            else if yesPFPs { // this weirdness is needed or animation won't run
                PfpAnimationViews(pfpUrls: pfpUrls, distances: distances, speeds: speeds)
            }
            else {
                ProgressView()
            }
        }
        .onAppear {
            let followingPfpUrls: [URL] = Array(la.followingCache.values).compactMap { $0.pfpURL }
            
            let followingPfpUrlsInCache: [URL] = Array(onlyAvailablePfpUrls(followingPfpUrls).shuffled().prefix(20))
            guard followingPfpUrlsInCache.count > 5 else {
                self.noPFPs = true
                return
            }
            
            self.distances = (0..<followingPfpUrlsInCache.count).map { _ in CGFloat.random(in: 80...120) }
            self.speeds = (0..<followingPfpUrlsInCache.count).map { _ in Double.random(in: 1.0...2.5) }
            self.pfpUrls = followingPfpUrlsInCache
            self.yesPFPs = true
        }
    }
}


struct CircleAnimationViews: View {
    @EnvironmentObject private var la: LoggedInAccount
    @State private var isAnimating = false
    
    private let circleCount = 10
    private let animationDuration: Double = 2.0
    
    // Array of random colors, distances, and speeds for outer circles
    private let colors: [Color] = (0..<10).map { _ in
        Color(
            red: Double.random(in: 0...1),
            green: Double.random(in: 0...1),
            blue: Double.random(in: 0...1)
        )
    }
    private var distances: [CGFloat] = (0..<10).map { _ in CGFloat.random(in: 80...120) }
    private var speeds: [Double] = (0..<10).map { _ in Double.random(in: 1.0...2.5) }
    
    var body: some View {
        ZStack {
            ForEach(0..<circleCount, id: \.self) { index in
                Circle()
                    .frame(width: 12, height: 12)
                    .foregroundColor(colors[index].opacity(isAnimating ? 0.0 : 0.7))
                    .offset(y: isAnimating ? 0 : -distances[index])
                    .rotationEffect(.degrees(Double.random(in: 0...360))) // Random starting angle
                    .rotationEffect(.degrees(isAnimating ? 180 : 0))
                    .scaleEffect(isAnimating ? 0.5 : 1.0)
                    .animation(
                        .easeIn(duration: speeds[index])
                            .repeatForever(autoreverses: false)
                            .delay(Double.random(in: 0...0.5)), // Random delay for staggered effect
                        value: isAnimating
                    )
            }
            
            if let accountPfpUrl = la.account.pictureUrl {
                TinyLoadingPFP(url: accountPfpUrl, size: 60)
                    .scaleEffect(isAnimating ? 1.3 : 0.9)
                    .animation(
                        .easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            }
            else {
                Circle()
                    .foregroundColor(Color.random)
                    .frame(width: 60, height: 60)
                    .scaleEffect(isAnimating ? 1.3 : 0.9)
                    .animation(
                        .easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct PfpAnimationViews: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var la: LoggedInAccount
    @State private var isAnimating = false

    private let pfpUrls: [URL]
    private let animationDuration: Double = 2.0
    private let distances: [CGFloat]
    private let speeds: [Double]
    
    init(pfpUrls: [URL], distances: [CGFloat], speeds: [Double]) {
        self.pfpUrls = pfpUrls
        self.distances = distances
        self.speeds = speeds
    }
    
    var body: some View {
        ZStack {
            ForEach(0..<pfpUrls.count, id: \.self) { index in
                TinyLoadingPFP(url: pfpUrls[index], size: 20)
                    .drawingGroup()
                    .offset(y: isAnimating ? 0 : -distances[index])
                    .rotationEffect(.degrees(Double.random(in: 0...360))) // Random starting angle
                    .rotationEffect(.degrees(isAnimating ? 180 : 0))
                    .scaleEffect(isAnimating ? 0.0 : 1.0)
                    .animation(
                        .easeIn(duration: speeds[index])
                            .repeatForever(autoreverses: false)
                            .delay(Double.random(in: 0...0.5)), // Random delay for staggered effect
                        value: isAnimating
                    )
            }
            
            if let accountPfpUrl = la.account.pictureUrl {
                TinyLoadingPFP(url: accountPfpUrl, size: 60)
                    .scaleEffect(isAnimating ? 1.3 : 0.9)
                    .animation(
                        .easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            }
            else {
                Circle()
                    .foregroundColor(theme.listBackground)
                    .frame(width: 60, height: 60)
                    .scaleEffect(isAnimating ? 1.3 : 0.9)
                    .animation(
                        .easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct FetchingAnimationView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadFollows()
            pe.loadContacts()
            pe.loadContactLists()
            _ = pe.loadAccount()
        
            
            if let fc = AccountsState.shared.loggedInAccount?.account.loadFollowingCache() {
                AccountsState.shared.loggedInAccount?.followingCache = fc
            }

            
        }) {
            FetchingAnimationView()
                .preferredColorScheme(.light)
        }
    }
}

func onlyAvailablePfpUrls(_ urls: [URL]) -> [URL] {
    return urls.filter { hasFPFcacheFor(pfpImageRequestFor($0)) }
}

import Nuke
import NukeUI

struct TinyLoadingPFP: View {
    @Environment(\.theme) private var theme
    
    var url: URL
    var size: CGFloat = 12
    
    var body: some View {
        LazyImage(request: pfpImageRequestFor(url, overrideLowDataMode: true), transaction: .init(animation: .none)) { state in
            if let image = state.image {
                if state.imageContainer?.type == .gif {
                    image
                        .resizable() // BUG: Still .gif gets wrong dimensions, so need .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                }
                else {
                    image
                        .resizable()
                        .interpolation(.none)
                        .frame(width: size, height: size)
                }
            }
            else { theme.listBackground }
        }
        .pipeline(ImageProcessing.shared.pfp)
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
