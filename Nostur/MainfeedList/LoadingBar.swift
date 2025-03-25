//
//  LoadingBar.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/03/2025.
//

import SwiftUI

struct LoadingBar: View {
    @EnvironmentObject private var themes: Themes
    @Binding public var loadingBarViewState: LoadingBar.ViewState
    public let height: CGFloat = 2.0
    
    static private let offStates: Set<LoadingBar.ViewState> = Set([.finished, .off, .timeout])
    
    @State private var didAppear = false
    @State private var opacity: Double = 0.0
    @State private var viewState: ViewState = .starting {
        didSet {
            if opacity != 0.0 && Self.offStates.contains(viewState) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    opacity = 0.0
                }
            }
            
            if viewState == .finalLoad {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    opacity = 0.0
                    viewState = .finished
                    loadingBarViewState = .finished
                }
            }
        }
    }
    
    private var percentage: CGFloat {
        switch viewState {
        case .off:
            0.0
        case .starting:
            0.01
        case .connecting:
            0.1
        case .fetching:
            0.15
        case .earlyLoad:
            0.25
        case .secondFetching:
            0.80
        case .finalLoad:
            1.0
        case .finished:
            0.01
        case .timeout:
            0.01
        }
    }
    
    private func barWidth(_ width: CGFloat) -> CGFloat {
        return width * percentage
    }
    
    var body: some View {
        GeometryReader { geo in
            themes.theme.accent
                .frame(width: barWidth(geo.size.width))
        }
        .frame(height: height)
        .opacity(opacity)
        .onChange(of: loadingBarViewState) { newViewState in
            if newViewState == .finished && opacity != 0.0 {
                opacity = 0.0
            }
            else if newViewState != .off {
                opacity = 1.0
            }
            
            let duration = switch newViewState {
            case .off, .starting:
                0.01
            case .connecting:
                8.0
            case .fetching:
                6.5
            case .secondFetching:
                9.5
            case .earlyLoad:
                3.5
            case .finalLoad, .finished:
                0.05
            case .timeout:
                0.1
            }
            
            if opacity != 0.0 {
                withAnimation(.snappy(duration: duration)) {
#if DEBUG
                    print("🏁🏁 LoadingBar.onChange(of: viewState = \(newViewState)")
#endif
                    self.viewState = newViewState
                }
            }
            else {
                self.viewState = newViewState
            }
        }
    }
}

extension LoadingBar {
    enum ViewState {
        case off
        case starting
        case connecting
        case fetching
        case earlyLoad
        case secondFetching
        case finalLoad
        case finished
        case timeout
    }
}

@available(iOS 17.0, *)
#Preview {
    
    @Previewable @State var loadingBarViewState: LoadingBar.ViewState = .starting
    
    PreviewContainer {
        VStack {
            LoadingBar(loadingBarViewState: $loadingBarViewState)
            Spacer()
            Text("viewState: \(loadingBarViewState)")
            Spacer()
            Button("connecting") {
                loadingBarViewState = .connecting
            }
            Button("fetching") {
                loadingBarViewState = .fetching
            }
            Button("earlyLoad") {
                loadingBarViewState = .earlyLoad
            }
            Button("secondFetching") {
                loadingBarViewState = .secondFetching
            }
            Button("finalLoad") {
                loadingBarViewState = .finalLoad
            }
        }
    }
}
