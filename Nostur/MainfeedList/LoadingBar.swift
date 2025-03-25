//
//  LoadingBar.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/03/2025.
//

import SwiftUI

struct LoadingBar: View {
    
    @EnvironmentObject private var themes: Themes
    public let vm: NXColumnViewModel
    public let height: CGFloat = 2.0
    
    @State private var viewState: ViewState = .idle
    
    private var percentage: CGFloat {
        switch viewState {
        case .off:
            0.0
        case .idle:
            0.01
        case .connecting:
            0.1
        case .fetching:
            0.2
        case .earlyLoad:
            0.7
        case .finalLoad:
            1.0
        case .finished:
            1.0
        }
    }
    
    private func barWidth(_ maxWidth: CGFloat) -> CGFloat {
        maxWidth * percentage
    }
    
    var body: some View {
        GeometryReader { geo in
            themes.theme.accent
                .frame(width: barWidth(geo.size.width))
                .opacity(viewState == .finished ? 0 : 1)
        }
        .frame(height: height)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0)) {
                viewState = .connecting
            }
        }
        .onReceive(vm.speedTest.$loadingBarViewState) { newViewState in
            
            withAnimation(.snappy(duration: 0.05)) {
                self.viewState = newViewState
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if viewState == .finalLoad {
                        self.viewState = .finished
                    }
                }
            }
        }
    }
}

extension LoadingBar {
    enum ViewState {
        case off
        case idle
        case connecting
        case fetching
        case earlyLoad
        case finalLoad
        case finished
    }
}

#Preview {
    LoadingBar(vm: .init())
        .environmentObject(Themes.default)
}
