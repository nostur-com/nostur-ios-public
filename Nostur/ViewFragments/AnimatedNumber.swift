//
//  AnimatedNumber.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/05/2023.
//

import SwiftUI
import Combine

struct AnimatedNumber: View {

    private let number: Int
    
    init<T: BinaryInteger>(number: T) {
        self.number = Int(number)
    }
    
    var body: some View {
        if #available(iOS 26.0, *) {
            AnimatedNumber26(number: number)
        }
        else if #available(iOS 16.0, *) {
            AnimatedNumber16(number: number)
        }
        else {
            AnimatedNumber15(number: number)
        }
    }
}

@available(iOS 26, *)
struct AnimatedNumber26: View {
    
    private let number: Int
    
    init<T: BinaryInteger>(number: T) {
        self.number = Int(number)
    }
    
    var body: some View {
        Text(number, format: .number.notation((.compactName)))
            .multilineTextAlignment(.center)
            .animation(.snappy, value: number)
            .contentTransition(.numericText(countsDown: false))
    }
}

@available(iOS 16, *)
struct AnimatedNumber16: View {
    
    private let number: Int
    
    init<T: BinaryInteger>(number: T) {
        self.number = Int(number)
    }
    
    var body: some View {
        Text(String(number))
            .multilineTextAlignment(.center)
            .animation(.snappy, value: number)
            .contentTransition(.numericText(countsDown: false))
    }
}

struct AnimatedNumber15: View {
    
    static let numberHeight: CGFloat = 18.0
    private let number: Int
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
                    .offset(y: Self.numberHeight)
            }
            .offset(y: offset)
            .frame(height: Self.numberHeight)
            .clipped()
            .onAppear {
                guard currentNumber != number else { return }
                currentNumber = number
            }
            .onChange(of: number) { newNumber in
                guard currentNumber != newNumber, nextNumber != newNumber else { return }
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
                    offset -= Self.numberHeight
                }
            }
            .onDisappear {
                // Cancel all subscriptions (timers in this case)
                cancellables.removeAll()
            }
//            .border(Color.green)
    }
}

struct AnimatedNumberString: View {

    public let number: String
    
    var body: some View {
        if #available(iOS 16.0, *) {
            AnimatedNumberString16(number: number)
        }
        else {
            AnimatedNumberString15(number: number)
        }
    }
}

@available(iOS 16, *)
struct AnimatedNumberString16: View {
    
    public let number: String
    
    var body: some View {
        Text(number)
            .multilineTextAlignment(.center)
            .animation(.snappy, value: number)
            .contentTransition(.numericText(countsDown: false))
    }
}

struct AnimatedNumberString15: View {
    
    static let numberHeight = 18.0
    public let number: String
    @State private var currentNumber = ""
    @State private var nextNumber = ""
    @State private var offset = 0.0
    @State private var timer: Timer?
    
    var body: some View {
        Text(verbatim: currentNumber)
            .overlay(alignment:.bottom) {
                Text(verbatim: nextNumber)
                    .offset(y: Self.numberHeight)
            }
            .offset(y:offset)
            .frame(height: Self.numberHeight)
            .clipped()
            .onAppear {
                guard currentNumber != number else { return }
                currentNumber = number
            }
            .onChange(of: number) { newNumber in
                guard currentNumber != newNumber, nextNumber != newNumber else { return }
                nextNumber = newNumber
                
                timer?.invalidate()
                timer = Timer(timeInterval: 0.35, repeats: false, block: { timer in
                    currentNumber = nextNumber
                    offset = 0.0
                })
                timer?.fire()
                
                withAnimation(.linear(duration: 0.3)) {
                    offset -= Self.numberHeight
                }
            }
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
            }
            if #available(iOS 16.0, *) {
                AnimatedNumber(number: number)
            }
            else {
                AnimatedNumber15(number: number)
            }
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
