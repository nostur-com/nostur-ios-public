//
//  ListStyle.swift
//  RagiSmoothList
//
//  Created by ragingo on 2022/12/20.
//

import SwiftUI

public protocol RagiSmoothListStyle: Equatable {}

public typealias DefaultListStyle = PlainListStyle

public struct PlainListStyle: RagiSmoothListStyle {
    public init() {}
}

public struct GroupedListStyle: RagiSmoothListStyle {
    public init() {}
}

public struct InsetListStyle: RagiSmoothListStyle {
    public init() {}
}

public struct InsetGroupedListStyle: RagiSmoothListStyle {
    public init() {}
}

public struct SidebarListStyle: RagiSmoothListStyle {
    public init() {}
}

enum RagiSmoothListStyleKey: EnvironmentKey {
    static let defaultValue: any RagiSmoothListStyle = .automatic
}

extension EnvironmentValues {
    var ragiSmoothListStyle: any RagiSmoothListStyle {
        get {
            self[RagiSmoothListStyleKey.self]
        }
        set {
            self[RagiSmoothListStyleKey.self] = newValue
        }
    }
}

public extension View {
    func ragiSmoothListStyle<S>(_ style: S) -> some View where S: RagiSmoothListStyle {
        environment(\.ragiSmoothListStyle, style)
    }
}

public extension RagiSmoothListStyle where Self == DefaultListStyle {
    static var automatic: DefaultListStyle { .init() }
}

public extension RagiSmoothListStyle where Self == SidebarListStyle {
    static var sidebar: SidebarListStyle { .init() }
}

public extension RagiSmoothListStyle where Self == InsetGroupedListStyle {
    static var insetGrouped: InsetGroupedListStyle { .init() }
}

public extension RagiSmoothListStyle where Self == GroupedListStyle {
    static var grouped: GroupedListStyle { .init() }
}

public extension RagiSmoothListStyle where Self == InsetListStyle {
    static var inset: InsetListStyle { .init() }
}

public extension RagiSmoothListStyle where Self == PlainListStyle {
    static var plain: PlainListStyle { .init() }
}
