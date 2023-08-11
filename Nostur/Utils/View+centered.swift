//
//  View+centered.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/03/2023.
//

import SwiftUI

struct CenteredView: ViewModifier {
    func body(content: Content) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                content
                Spacer()
            }
            Spacer()
        }
    }
}

struct VerticallyCenteredView: ViewModifier {
    func body(content: Content) -> some View {
        VStack {
            Spacer()
            content
            Spacer()
        }
    }
}

struct HorizontallyCenteredView: ViewModifier {
    func body(content: Content) -> some View {
        HStack {
            Spacer()
            content
            Spacer()
        }
    }
}

struct BoxShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Rectangle()
                    .foregroundColor(Color("BackgroundColor"))
                    .shadow(color: Color.gray.opacity(0.25), radius: 5)
            )
    }
}

struct RoundedBoxShadow: ViewModifier {
    var backgroundColor:Color = Color.systemBackground
    static let shadowColor = Color("ShadowColor").opacity(0.25)
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10.0)
                    .foregroundColor(backgroundColor)
                    .shadow(color: Self.shadowColor, radius: 5)
            )
    }
}

extension View {
    func centered() -> some View {
        modifier(CenteredView())
    }
    func vCentered() -> some View {
        modifier(VerticallyCenteredView())
    }
    func hCentered() -> some View {
        modifier(HorizontallyCenteredView())
    }
    
    func boxShadow() -> some View {
        modifier(BoxShadow())
    }
    
    func roundedBoxShadow(backgroundColor:Color = Color.systemBackground) -> some View {
        modifier(RoundedBoxShadow(backgroundColor:backgroundColor))
    }
}
