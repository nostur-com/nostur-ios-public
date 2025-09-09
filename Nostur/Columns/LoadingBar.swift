//
//  LoadingBar.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/03/2025.
//

import SwiftUI

struct LoadingBar: View {
    @Environment(\.theme) private var theme
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
            
            if viewState == .finalLoad && oldValue != .finalLoad {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    opacity = 0.0
                    viewState = .finished
                    if loadingBarViewState != .finished {
                        loadingBarViewState = .finished
                    }
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
            theme.accent
                .frame(width: barWidth(geo.size.width))
        }
        .frame(height: height)
        .opacity(opacity)
        .onChange(of: loadingBarViewState) { [oldViewState = self.viewState] newViewState in
            guard newViewState != oldViewState else { return }
            guard newViewState != .finished else { return } // .finished is only set on didSet with .finalLoad
            
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
            
            let goingBackward = [.connecting,.earlyLoad,.fetching,.secondFetching].contains(newViewState) && newViewState.rawValue < oldViewState.rawValue
            
            if goingBackward {
                self.opacity = 0.0
                self.viewState = .off
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
                    self.opacity = 1.0
                    withAnimation(.snappy(duration: duration)) {
#if DEBUG
                        L.og.debug("🏁🏁 LoadingBar.onChange(of:loadingBarViewState) Setting viewState to: \(newViewState.rawValue) -[LOG]-")
#endif
                        self.viewState = newViewState
                    }
                }
                return
            }
            
            if !goingBackward && newViewState != .off && opacity != 1.0 {
                opacity = 1.0
            }
            
            if opacity != 0.0 {
                withAnimation(.snappy(duration: duration)) {
#if DEBUG
                    L.og.debug("🏁🏁 LoadingBar.onChange(of:loadingBarViewState) Setting viewState to: \(newViewState.rawValue) -[LOG]-")
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
    enum ViewState: Int {
        case off = 0
        case starting = 1
        case connecting = 2
        case fetching = 3
        case earlyLoad = 4
        case secondFetching = 5
        case finalLoad = 6
        case finished = 7
        case timeout = 8
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
            
            Divider()
            
            Button("finished") {
                loadingBarViewState = .finished
            }
            
            Button("timeout") {
                loadingBarViewState = .timeout
            }
        }
    }
}
