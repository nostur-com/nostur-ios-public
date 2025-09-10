//
//  LightningEffect.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/06/2023.
//

import SwiftUI

struct LightningStrikeShape: Shape {
    let lineWidth: CGFloat
    let amplitude: CGFloat
    let startX: CGFloat
    let endLocation: CGPoint
    
    func path(in rect: CGRect) -> Path {
        let endLocation = CGPoint(x: endLocation.x + 12, y: endLocation.y - 32) // Small correction or the strike is off a bit
        var path = Path()
        let startX = startX
        let startY = rect.minY
        let segments = Int(((endLocation.y - startY) / 80)) // number of segments in the lightning strike
        let segmentWidth = (endLocation.x - startX) / CGFloat(segments)
        let segmentHeight = (endLocation.y - startY) / CGFloat(segments) // height of each segmentY
        
        path.move(to: CGPoint(x: startX, y: rect.minY))
        //        var segmentX = startX
        //        for i in 0..<segments {
        //            let segmentX = startX + CGFloat(i) * segmentWidth
        //            let segmentY = (i % 2 == 0 ? rect.minY + amplitude : rect.minY - amplitude) + CGFloat(i) * segmentHeight
        //            path.addLine(to: CGPoint(x: segmentX, y: segmentY))
        //        }
        
        // straight line
        for i in 0..<segments {
            let segmentX = startX + CGFloat(i) * segmentWidth
            //            let segmentY = CGFloat(i) * segmentHeight
            let segmentY = (i % 2 == 0 ? startY + amplitude : startY - amplitude) + CGFloat(i) * segmentHeight
            path.addLine(to: CGPoint(x: segmentX, y: segmentY))
        }
        path.addLine(to: CGPoint(x: endLocation.x, y: endLocation.y))
        
        return path.strokedPath(.init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}

struct SideStrikeShape: Shape {
    let lineWidth: CGFloat
    let amplitude: CGFloat
    
    func path(in rect: CGRect) -> Path {
        let endLocation = CGPoint(x: rect.width, y: rect.height/2)
//        let _ = print(rect)
        var path = Path()
        let startX = 0.0
        let startY = rect.height
        let segments = Int(endLocation.x / 40) // number of segments in the lightning strike
        let segmentWidth = (endLocation.x - startX) / CGFloat(segments)
        let segmentHeight = (endLocation.y - startY) / CGFloat(segments) // height of each segmentY
        
        path.move(to: CGPoint(x: startX, y: startY))
        
        // straight line
        for i in 0..<segments {
            let segmentX = startX + CGFloat(i) * segmentWidth
            let segmentY = (i % 2 == 0 ? startY + amplitude : startY - amplitude) + CGFloat(i) * segmentHeight
            path.addLine(to: CGPoint(x: segmentX, y: segmentY))
        }
        path.addLine(to: CGPoint(x: endLocation.x, y: endLocation.y))
        
        return path.strokedPath(.init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}

struct LightingEffectTester: View {
    @State var activeColor = Color.gray
    
    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .trailing) {
                Spacer()
                Text(verbatim:"Example view - text Example view  1 ")
                Text(verbatim:"Example view - text 2 ")
                Text(verbatim:"Example view - text 3 ")
                Image("BoltIcon")
                    .foregroundColor(activeColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(
                        GeometryReader { geo in
                            Color.white.opacity(0.001)
                                .onTapGesture {
                                    sendNotification(.lightningStrike, LightningStrike(location:geo.frame(in: .global).origin, amount:Double.random(in: 1000...119000), sideStrikeWidth: 200.0))
                                    withAnimation(.easeIn(duration: 0.25).delay(0.25)) {// wait 0.25 for the strike
                                        activeColor = .yellow
                                    }
                                }
                        }
                    )
                
                Text(verbatim:"Example view - text 4 ")
                Text(verbatim:"Example view - text 5 ")
                Text(verbatim:"Example view - text 6 ")
                Spacer()
            }
        }
        .withLightningEffect()
    }
}

struct LightningEffect_Previews: PreviewProvider {
    static var previews: some View {
        LightingEffectTester()
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}


struct LightningStrike: Identifiable {
    let id = UUID()
    let location:CGPoint
    let amount:Double
    
    var sideStrikeWidth:CGFloat?
}


public extension View {
    func withLightningEffect() -> some View {
        modifier(WithLightningEffect())
    }
}

private struct WithLightningEffect: ViewModifier {
    
    enum BoltState {
        case awaiting
        case striking
        case striking2
        case striked
    }
    
    var boltWidth:CGFloat {
        switch bolt {
        case .awaiting:
            return 3
        case .striking, .striking2:
            return 3
        case .striked:
            return 6
        }
    }
    
    @State var bolt:BoltState = .awaiting
    @State var darkness = false
    
    @State var boltColorBegin = Color.yellow
    @State var boltColorMiddle = Color.yellow.opacity(0.4)
    @State var boltColorEnd = Color.yellow.opacity(0.2)
    @State var startX:CGFloat = 0.0
    @State var endLocation:CGPoint = .zero
    @State var boltScale = 1.0
    @State var boltOpacity = 0.0
    @State var amount:Double = 0.0
    
    @State var sideStrikeWidth:CGFloat? = nil
    
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(darkness ? 0.5 : 0)
                    LightningStrikeShape(lineWidth: boltWidth, amplitude: 35, startX: startX, endLocation: endLocation)
                        .stroke(LinearGradient(gradient: Gradient(colors: [boltColorBegin, boltColorMiddle, boltColorEnd]), startPoint: .top, endPoint: .bottom), lineWidth: boltWidth)
                        .opacity(bolt != .awaiting ? 1 : 0)
                    Image("BoltIconActive").foregroundColor(.yellow)
                        .padding(.horizontal, 40)
                        .overlay(alignment: .topLeading) {
                            Text(amount, format: .number.notation((.compactName)))
                                .foregroundColor(.yellow)
                                .shadow(color: .black, radius: 1)
                        }
                        .scaleEffect(boltScale)
                        .offset(x: endLocation.x + 12 - 40, y: endLocation.y - 44)
                        .opacity(boltOpacity)
                    
                    if sideStrikeWidth != nil {
                        SideStrikeShape(lineWidth: boltWidth, amplitude: 5)
                            .stroke(Color.yellow, lineWidth: boltWidth)
                            .opacity(bolt != .awaiting ? 1 : 0)

                            .frame(width: endLocation.x - 50, height: 50.0)
                            .offset(x: 60.0, y: endLocation.y - 57)
                    }
                    
                    
                }.opacity(bolt == .awaiting ? 1.0 : 1.0)
            }
            .onReceive(receiveNotification(.lightningStrike)) { notification in
                let strike = notification.object as! LightningStrike
                endLocation = strike.location
                bolt = .awaiting
                amount = strike.amount
                startX = CGFloat.random(in: UIScreen.main.bounds.minX...UIScreen.main.bounds.maxX)
                
                sideStrikeWidth = strike.sideStrikeWidth
                
                zap()
            }
    }
    
    func zap() {
        withAnimation(.linear(duration: 0.1).delay(0.05)) {
            darkness = true
            bolt = .striking
        }
        withAnimation(.linear(duration: 0.1).delay(0.15)) {
            bolt = .striking2
            boltColorMiddle = Color.yellow.opacity(0.7)
            boltColorEnd =  Color.yellow.opacity(0.4)
        }
        withAnimation(.linear(duration: 0.1).delay(0.25)) {
            bolt = .striked
            boltColorMiddle = Color.yellow
            boltColorEnd =  Color.yellow
            boltScale = 3.5
            boltOpacity = 1.0
        }
        withAnimation(.linear(duration: 0.2).delay(0.45)) {
            darkness = false
            bolt = .awaiting
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            boltColorBegin = Color.yellow
            boltColorMiddle = Color.yellow.opacity(0.4)
            boltColorEnd = Color.yellow.opacity(0.2)
            boltScale = 1.0
            boltOpacity = 0.0
            sideStrikeWidth = nil
        }
    }
}
