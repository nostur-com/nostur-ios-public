// Code taken from https://github.com/MisnikovRoman/OdometerLabel

import SwiftUI
import Foundation

struct RollingNumberLabel: View {
    
    struct Settings {
        var rounds: Int
        var interNumberDelay: Double
        var numberAnimationDuration: Double
        
        static var basic: Self {
            .init(rounds: 0, interNumberDelay: 0.1, numberAnimationDuration: 0.7)
        }
    }
    
//    let startingNumber: Int
    let number: Int
    let settings: Settings
    
    init(_ number: Int, settings: Settings = .basic) {
//        self.startingNumber = startingNumber
        self.number = number
        self.settings = settings
    }
    
    init(_ number: Int64, settings: Settings = .basic) {
//        self.startingNumber = Int(startingNumber)
        self.number = Int(number)
        self.settings = settings
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(number.splitToTargets(), id: \.id) { target in
                OneRollingNumberView(target: target, settings: settings)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

struct RollingOnUpdateNumber: View {
    var number:Int
    @State var didUpdate = false
//    @State var oldNumber:Int = 0
    
    init(_ number:Int) {
        self.number = number
    }
    
    var body: some View {
        if (didUpdate) {
            RollingNumberLabel(number)
        }
        else {
            Text("\(number)")
                .onChange(of: number) { newValue in
                    if (newValue != number) {
//                        oldNumber = number
                        didUpdate = true
                    }
                }
        }
    }
}

struct RollingNumberViewWrapper: View {
    @State private var number = 3
    var body: some View {
        VStack {
            RollingOnUpdateNumber(number)
            Button("ddd") { number = number + 1}
        }
    }
}

struct RollingNumberView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            RollingNumberViewWrapper()
        }
        
    }
}

struct OneRollingNumberView: View {

    struct Debug {
        var isClipped: Bool
        var showBorder: Bool
        var from: Int
        var to: Int
        var isIncreasing: Bool
        var rounds: Int
        var duration: Double
        var animationToggle: Bool
        var delay: Double
    }
    
    let target: TargetNumber
    let settings: RollingNumberLabel.Settings
    let debug: Debug
    
    init(target: TargetNumber, settings: RollingNumberLabel.Settings = .basic, debug: Debug? = nil) {
//        self.selectedNumber = startingNumber
        self.target = target
        self.settings = settings
        self.debug = debug ?? .init(isClipped: true, showBorder: false, from: 0, to: 0, isIncreasing: true, rounds: 0, duration: 1.0, animationToggle: false, delay: 0.0)
    }
    
    @State private var selectedNumber: Int = 0
    private let oneNumberHeight: CGFloat = 20

    var body: some View {
        ZStack {
            ForEach(0...10, id: \.self) { i in
                Text("\(i % 10)")
                    .offset(x: 0, y: CGFloat(i) * oneNumberHeight + totalOffset)
            }
        }
        .clipped(isActive: debug.isClipped)
        .border(Color.red.opacity(debug.showBorder ? 0.2 : 0.0))
        .onChange(of: target) { new in
             animateWithOneExtraRound(from: target, to: new)
        }
        .onAppear {
            directionalAnimate(
                from: 0,
                to: target.main,
                isIncreasing: true,
                fullRoundsCount: settings.rounds,
                duration: settings.numberAnimationDuration,
                delay: target.id.double * settings.interNumberDelay
            )
        }
        .onDisappear {
            directionalAnimate(
                from: target.main,
                to: 0,
                isIncreasing: false,
                fullRoundsCount: settings.rounds,
                duration: settings.numberAnimationDuration,
                delay: target.id.double * settings.interNumberDelay
            )
        }
        .onChange(of: debug.animationToggle) { new in
            directionalAnimate(from: debug.from, to: debug.to, isIncreasing: debug.isIncreasing, fullRoundsCount: debug.rounds, duration: debug.duration, delay: debug.delay)
        }
    }
    
    var totalOffset: CGFloat {
        CGFloat(selectedNumber) * oneNumberHeight * -1
    }
    
    // MARK: - Animation
    
    /// Прямая анимация от одного числа к другому
    /// - Parameters:
    ///   - from: начальное положение
    ///   - to: конечное положение
    ///   - repeatCount: сколько раз повторить анимацию
    ///   - duration: время периода анимации
    ///   - delay: задержка начала анимации
    ///   - curve: Вид кривой для анимации
    func dummyAnimate(
        from: Int,
        to: Int,
        repeatCount: Int = 1,
        duration: Double,
        delay: Double = 0,
        curve: Animation.Curve = .linear
    ) {
        Animation
            .linear(duration: 0.001)
            .delay(delay)
            .animate { selectedNumber = from }
        Animation
            .curve(curve, duration: duration)
            .repeatCount(repeatCount, autoreverses: false)
            .delay(delay + 0.001)
            .animate {
//                print("🦉\(target.id) Animate \(from)->\(to) \(duration)sec x\(repeatCount) after \(delay)sec")
                selectedNumber = to
            }
    }
    
    /// Анимация числа вращением за заданное время
    /// - Parameters:
    ///   - from: начальное число
    ///   - to: конечное число
    ///   - isIncreasing: true - числа вращаются от меньшего к большего; false - в обратную сторону
    ///   - fullRoundsCount: кол-во полных оборотов от 0,1,... -> ...,9,0
    ///   - duration: общая длительность анимации
    ///   - delay: задержка начала анимации
    func directionalAnimate(
        from: Int,
        to: Int,
        isIncreasing: Bool,
        fullRoundsCount: Int = 0,
        duration: Double,
        delay: Double = 0
    ) {
        
        let stepsCount1 = isIncreasing
            ? 10 - from // увеличиваем до 10 (дальний ноль)
            : from      // уменьшаем до 0 (ближний ноль)
        let stepsCount2 = 10 * fullRoundsCount // делаем несколько полных оборотов
        let stepsCount3 = isIncreasing
            ? to      // доходим до нужного числа от 0
            : 10 - to // возвращаемся до нужнуго числа от 10 (дальний ноль)
        let totalEditedSteps = stepsCount1 + stepsCount2 + stepsCount3 // новое кол-во шагов
        
        let editedStepDuration = duration / totalEditedSteps.double // новое время шага (переключения с одного числа на другое)
        
        let t1 = stepsCount1.double * editedStepDuration // время первой части анимации
        let t2 = stepsCount2.double * editedStepDuration // время второй части анимации
        let t3 = stepsCount3.double * editedStepDuration // время третьей части анимации
        
        if isIncreasing, fullRoundsCount == 0, from < to {
            dummyAnimate(from: from, to: to, duration: t1 + t2 + t3, delay: delay, curve: .easeInOut)
        } else if !isIncreasing, fullRoundsCount == 0, from > to {
            dummyAnimate(from: from, to: to, duration: t1 + t2 + t3, delay: delay, curve: .easeInOut)
        } else if isIncreasing {
            dummyAnimate(from: from, to: 10, duration: t1, delay: delay, curve: .easeIn)
            if fullRoundsCount > 0 {
                dummyAnimate(from: 0, to: 10, repeatCount: fullRoundsCount, duration: t2 / fullRoundsCount.double, delay: delay + t1)
            }
            dummyAnimate(from: 0, to: to, duration: t3, delay: delay + t1 + t2, curve: .easeOut)
        } else {
            dummyAnimate(from: from, to: 0, duration: t1, delay: delay, curve: .easeIn)
            if fullRoundsCount > 0 {
                dummyAnimate(from: 10, to: 0, repeatCount: fullRoundsCount, duration: t2 / fullRoundsCount.double, delay: delay + t1)
            }
            dummyAnimate(from: 10, to: to, duration: t3, delay: delay + t1 + t2, curve: .easeOut)
        }
    }
    
    func animateWithOneExtraRound(from oldTarget: TargetNumber, to newTarget: TargetNumber) {
        
        let isIncreasing = newTarget.origin > oldTarget.origin
        let delay = newTarget.id.double * settings.interNumberDelay
        
        directionalAnimate(
            from: oldTarget.main,
            to: newTarget.main,
            isIncreasing: isIncreasing,
            fullRoundsCount: settings.rounds,
            duration: settings.numberAnimationDuration,
            delay: delay
        )
    }
}



struct TargetNumber: Hashable {
    // уникальный идентификатор, а также порядковый номер цифры в числе справа (начиная с нуля)
    // например, для числа 2738
    //   id: 3 2 1 0
    //    n: 2 7 3 8
    let id: Int
    
    // максимальный id
    let maxId: Int
    
    // "кол-во десятков"
    // например, для числа 2738 previous = 273
    let previous: Int
    
    // основное число (последнее)
    // например, для числа 2738 main = 8
    let main: Int
    
    // оригинальное число
    let origin: Int
    
    var lapTime: Double {
        0.3 * id.double + 0.2
    }
    
    var value: Int {
        previous * 10 + main
    }
    
    func steps(to target: TargetNumber) -> Int {
        abs(value - target.value)
    }
}

extension TargetNumber {
    static var zero: Self {
        .init(id: 0, maxId: 0, previous: 0, main: 0, origin: 0)
    }
}


protocol StringConvertible {
    init(_ text: String)
    func toString() -> String
    static func += (lhs: inout Self, rhs: Self)
    static func -= (lhs: inout Self, rhs: Self)
}

extension Int: StringConvertible {
    init(_ text: String) { self = .init(text) ?? 0 }
    func toString() -> String { "\(self)" }
}

extension Double: StringConvertible {
    init(_ text: String) { self = .init(text) ?? 0 }
    func toString() -> String { String(format: "%.2f", self) }
}

extension Int {
    var double: Double {
        Double(self)
    }
    
    func splitToTargets() -> [TargetNumber] {
        guard self != 0 else { return [.zero] }
        
        var i = self
        var targets = [TargetNumber]()
        var step = 0
        
        let maxId = String(self).count - 1
        
        while i > 0 {
            targets.append(.init(id: step, maxId: maxId, previous: i / 10, main: i % 10, origin: self))
            i = i / 10
            step += 1
        }
        return targets.reversed()
    }
}

extension Decimal {
    var doubleValue: Double {
        return NSDecimalNumber(decimal: self).doubleValue
    }
}

struct ClippedModifier: ViewModifier {
    let isActive: Bool
    
    func body(content: Content) -> some View {
        if isActive {
            content.clipped()
        } else {
            content
        }
    }
}

extension View {
    func clipped(isActive: Bool) -> some View {
        self.modifier(ClippedModifier(isActive: isActive))
    }
}


extension Animation {
    enum Curve {
        case linear, easeIn, easeOut, easeInOut
    }
    
    func animate(_ block: () -> Void) {
        withAnimation(self) { block() }
    }
    
    static func curve(_ curve: Curve, duration: Double = 0.3) -> Animation {
        switch curve {
        case .linear:
            return .linear(duration: duration)
        case .easeIn:
            return .easeIn(duration: duration)
        case .easeOut:
            return .easeOut(duration: duration)
        case .easeInOut:
            return .easeInOut(duration: duration)
        }
    }
}

