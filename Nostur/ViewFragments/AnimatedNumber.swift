//
//  AnimatedNumber.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/05/2023.
//

import SwiftUI
import Combine

struct AnimatedNumber: View {
    
    let numberHeight: CGFloat = 18.0
    let number: Int
    @State private var currentNumber = 0
    @State private var nextNumber = 0
    @State private var offset: CGFloat = 0.0
    @State private var cancellables = Set<AnyCancellable>()
    
    init<T: BinaryInteger>(number: T) {
        self.number = Int(number)
    }
    
    var body: some View {
        Text(String(currentNumber))
            .overlay(alignment: .bottom) {
                Text(String(nextNumber))
                    .offset(y: numberHeight)
            }
            .offset(y: offset)
            .frame(height: numberHeight)
            .clipped()
            .onAppear {
                currentNumber = number
            }
            .onChange(of: number) { newNumber in
                guard currentNumber != newNumber else { return }
                nextNumber = newNumber
                
                // Cancel previous timer
                cancellables.removeAll()
                
                // Start new timer
                Just(())
                    .delay(for: .seconds(0.35), scheduler: RunLoop.main)
                    .sink { _ in
                        currentNumber = nextNumber
                        offset = 0.0
                    }
                    .store(in: &cancellables)
                
                withAnimation(.linear(duration: 0.3)) {
                    offset -= numberHeight
                }
            }
            .onDisappear {
                // Cancel all subscriptions (timers in this case)
                cancellables.removeAll()
            }
    }
}

struct AnimatedNumberString: View {
    
    let numberHeight = 18.0
    let number:String
    @State var currentNumber = ""
    @State var nextNumber = ""
    @State var offset = 0.0
    @State var timer:Timer?
    
    var body: some View {
        Text(verbatim: currentNumber)
            .overlay(alignment:.bottom) {
                Text(verbatim: nextNumber)
                    .offset(y:numberHeight)
            }
            .offset(y:offset)
            .frame(height: numberHeight)
            .clipped()
            .onAppear {
                currentNumber = number
            }
            .onChange(of: number) { newNumber in
                guard currentNumber != newNumber else { return }
                nextNumber = newNumber
                
                timer?.invalidate()
                timer = Timer(timeInterval: 0.35, repeats: false, block: { timer in
                    currentNumber = nextNumber
                    offset = 0.0
                })
                timer?.fire()
                
                withAnimation(.linear(duration: 0.3)) {
                    offset -= numberHeight
                }
            }
    }
}

extension View {
    
    // This seems to work to stop views from flying around the screen
    // Works better than .transaction { t in t.animation = nil }
    func withoutAnimation() -> some View {
        self.animation(nil, value: UUID())
    }
}

struct AnimatedNumberPreviewContainer: View {
    
    @State private var number = 0
    @State private var visibleRed = false
    
    var body: some View {
        VStack(spacing: 10) {
            if visibleRed {
                Color.red
                    .frame(width: 200, height: 300)
//                    .transaction { t in t.animation = nil }
            }
            
            AnimatedNumber(number: number)
                
//                .transaction { t in t.animation = nil } // this breaks animation in child views
            
            
                .withoutAnimation() // <-- this doesn't break animation in child views, and correctly stop this view from moving around the screen
            
                
            
            Group {
                Button("+1") { number += 25 }
//                    .transaction { t in t.animation = nil }
                
                Button("toggle red") {
                    withAnimation {
                        visibleRed.toggle()
                    }
                }
//                .transaction { t in t.animation = nil }
            }
            .buttonStyle(.borderedProminent)
            .transaction { t in t.animation = nil }
//            .withoutAnimation()
                
            Spacer()
        }
//        .transaction { t in t.animation = nil } // <-- This breaks animation on the AnimatedNumber child view (Makes sense per docs, use only on leaf views, not containers)
//        .withoutAnimation() // <-- This breaks animation on the AnimatedNumber child view (same as per docs)
    }
}

struct AnimatedNumber_Previews: PreviewProvider {
    
    static var previews: some View {
        AnimatedNumberPreviewContainer()
//            .withoutAnimation() <-- doesn't stop child views from flying around
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}
