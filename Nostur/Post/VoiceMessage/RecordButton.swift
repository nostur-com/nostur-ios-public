//
//  RecordButton.swift
//
//  Created by Joshua Galvan on 5/31/23.
//  Modified by Fabian Lachman on 7/14/25.
//
//  Example usage:
//
//    RecordButton(isRecording: $isRecording) {
//      print("Start")
//    } stopAction: {
//      print("Stop")
//    }
//    .frame(width: 70, height: 70)
//

import SwiftUI

struct RecordButton: View {
    @State var isRecording: Bool = false
    let buttonColor: Color
    let borderColor: Color
    let animation: Animation
    let startAction: () -> Void
    let stopAction: () -> Void
    
    init(
        buttonColor: Color = .red,
        borderColor: Color = .white,
        animation: Animation = .easeInOut(duration: 0.25),
        startAction: @escaping () -> Void,
        stopAction: @escaping () -> Void
    ) {
        self.buttonColor = buttonColor
        self.borderColor = borderColor
        self.animation = animation
        self.startAction = startAction
        self.stopAction = stopAction
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                let minDimension = min(geometry.size.width, geometry.size.height)
                
                Button {
                    if isRecording {
                        deactivate()
                    } else {
                        activate()
                    }
                } label: {
                    RecordButtonShape(isRecording: isRecording)
                        .fill(buttonColor)
                        .overlay {
                            if !isRecording {
                                Image(systemName: "mic")
                                    .font(.system(size: minDimension * 0.32, weight: .medium))
                                    .foregroundColor(Color.white)
                            }
                        }
                }
                Circle()
                    .strokeBorder(lineWidth: minDimension * 0.04)
                    .foregroundColor(borderColor.opacity(0.8))
            }
        }
    }
    
    private func activate() {
        startAction()
        withAnimation(animation) {
            isRecording.toggle()
        }
    }
    
    private func deactivate() {
        stopAction()
        withAnimation(animation) {
            isRecording.toggle()
        }
    }
}

struct RecordButtonShape: Shape {
    var shapeRadius: CGFloat
    var distanceFromCardinal: CGFloat
    // `b` and `c` come from here: https://spencermortensen.com/articles/bezier-circle/
    var b: CGFloat
    var c: CGFloat
    
    init(isRecording: Bool) {
        self.shapeRadius = isRecording ? 1.0 : 0.0
        self.distanceFromCardinal = isRecording ? 1.0 : 0.0
        self.b = isRecording ? 0.90 : 0.553
        self.c = isRecording ? 1.00 : 0.999
    }
    
    var animatableData: AnimatablePair<Double, AnimatablePair<Double, AnimatablePair<Double, Double>>> {
        get {
            AnimatablePair(Double(shapeRadius),
                           AnimatablePair(Double(distanceFromCardinal),
                                          AnimatablePair(Double(b), Double(c))))
        }
        set {
            shapeRadius = Double(newValue.first)
            distanceFromCardinal = Double(newValue.second.first)
            b = Double(newValue.second.second.first)
            c = Double(newValue.second.second.second)
        }
    }
    
    func path(in rect: CGRect) -> Path {
        let minDimension = min(rect.maxX, rect.maxY)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = (minDimension / 2 * 0.85) - (shapeRadius * minDimension * 0.25)
        let movementFactor = 0.65
        
        let rightTop = CGPoint(x: center.x + radius, y: center.y - radius * movementFactor * distanceFromCardinal)
        let rightBottom = CGPoint(x: center.x + radius, y: center.y + radius * movementFactor * distanceFromCardinal)
        
        let topRight = CGPoint(x: center.x + radius * movementFactor * distanceFromCardinal, y: center.y - radius)
        let topLeft = CGPoint(x: center.x - radius * movementFactor * distanceFromCardinal, y: center.y - radius)
        
        let leftTop = CGPoint(x: center.x - radius, y: center.y - radius * movementFactor * distanceFromCardinal)
        let leftBottom = CGPoint(x: center.x - radius, y: center.y + radius * movementFactor * distanceFromCardinal)
        
        let bottomRight = CGPoint(x: center.x + radius * movementFactor * distanceFromCardinal, y: center.y + radius)
        let bottomLeft = CGPoint(x: center.x - radius * movementFactor * distanceFromCardinal, y: center.y + radius)
        
        let topRightControl1 = CGPoint(x: center.x + radius * c, y: center.y - radius * b)
        let topRightControl2 = CGPoint(x: center.x + radius * b, y: center.y - radius * c)
        
        let topLeftControl1 = CGPoint(x: center.x - radius * b, y: center.y - radius * c)
        let topLeftControl2 = CGPoint(x: center.x - radius * c, y: center.y - radius * b)
        
        let bottomLeftControl1 = CGPoint(x: center.x - radius * c, y: center.y + radius * b)
        let bottomLeftControl2 = CGPoint(x: center.x - radius * b, y: center.y + radius * c)
        
        let bottomRightControl1 = CGPoint(x: center.x + radius * b, y: center.y + radius * c)
        let bottomRightControl2 = CGPoint(x: center.x + radius * c, y: center.y + radius * b)
    
        var path = Path()
        
        path.move(to: rightTop)
        path.addCurve(to: topRight, control1: topRightControl1, control2: topRightControl2)
        path.addLine(to: topLeft)
        path.addCurve(to: leftTop, control1: topLeftControl1, control2: topLeftControl2)
        path.addLine(to: leftBottom)
        path.addCurve(to: bottomLeft, control1: bottomLeftControl1, control2: bottomLeftControl2)
        path.addLine(to: bottomRight)
        path.addCurve(to: rightBottom, control1: bottomRightControl1, control2: bottomRightControl2)
        path.addLine(to: rightTop)

        return path
    }
}

#Preview("Recording Button") {
    VStack {
        RecordButton(startAction: {}, stopAction: {})
            .frame(height: 100)
    }
}
