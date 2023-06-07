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
}
