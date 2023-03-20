//
//  ShimmerAnimation.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/03/2023.
//

import SwiftUI

struct SharpShapesLoadingAnimation: View {
    
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Color.white.edgesIgnoringSafeArea(.all)
            
            VStack {
                Image(systemName: "square.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.gray)
                    .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                    .animation(
                        Animation.linear(duration: 1)
                            .repeatForever(autoreverses: false)
                    )
                
                HStack(spacing: 20) {
                    Rectangle()
                        .frame(width: 10, height: 40)
                        .cornerRadius(5)
                        .foregroundColor(.gray)
                        .scaleEffect(isAnimating ? 1.5 : 1)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(0.2)
                        )
                    
                    Rectangle()
                        .frame(width: 10, height: 30)
                        .cornerRadius(5)
                        .foregroundColor(.gray)
                        .scaleEffect(isAnimating ? 1.2 : 1)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(0.4)
                        )
                    
                    Rectangle()
                        .frame(width: 10, height: 20)
                        .cornerRadius(5)
                        .foregroundColor(.gray)
                        .scaleEffect(isAnimating ? 0.9 : 1)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(0.6)
                        )
                }
                .padding(.top, 20)
            }
        }
        .onAppear {
            self.isAnimating = true
        }
    }
}


struct ComplexLoadingAnimation: View {
    
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .foregroundColor(.green)
                    .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                    .animation(
                        Animation.linear(duration: 2)
                            .repeatForever(autoreverses: false)
                    )
                
                Text("Loading...")
                    .foregroundColor(.gray)
                    .font(.headline)
                    .padding(.top, 20)
                
                HStack(spacing: 20) {
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .frame(width: 50, height: 50)
                        .foregroundColor(.red)
                        .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                        .animation(
                            Animation.linear(duration: 1)
                                .repeatForever(autoreverses: false)
                        )
                    
                    Circle()
                        .trim(from: 0.3, to: 0.6)
                        .stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .frame(width: 50, height: 50)
                        .foregroundColor(.yellow)
                        .rotationEffect(Angle(degrees: isAnimating ? -360 : 0))
                        .animation(
                            Animation.linear(duration: 1)
                                .repeatForever(autoreverses: false)
                        )
                    
                    Circle()
                        .trim(from: 0.6, to: 0.9)
                        .stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .frame(width: 50, height: 50)
                        .foregroundColor(.blue)
                        .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                        .animation(
                            Animation.linear(duration: 1)
                                .repeatForever(autoreverses: false)
                        )
                }
                .padding(.top, 20)
            }
        }
        .onAppear {
            self.isAnimating = true
        }
    }
}

struct BirdLoadingAnimation: View {
    
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Color.white.edgesIgnoringSafeArea(.all)
            
            VStack {
                Image(systemName: "square.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.gray)
                    .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                    .animation(
                        Animation.linear(duration: 1)
                            .repeatForever(autoreverses: false)
                    )
                
                HStack(spacing: 20) {
                    Rectangle()
                        .frame(width: 10, height: 40)
                        .cornerRadius(5)
                        .foregroundColor(.gray)
                        .scaleEffect(isAnimating ? 1.5 : 1)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(0.2)
                        )
                    
                    Rectangle()
                        .frame(width: 10, height: 30)
                        .cornerRadius(5)
                        .foregroundColor(.gray)
                        .scaleEffect(isAnimating ? 1.2 : 1)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(0.4)
                        )
                    
                    Rectangle()
                        .frame(width: 10, height: 20)
                        .cornerRadius(5)
                        .foregroundColor(.gray)
                        .scaleEffect(isAnimating ? 0.9 : 1)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(0.6)
                        )
                }
                .padding(.top, 20)
                
                Image(systemName: "swift")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.gray)
                    .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                    .animation(
                        Animation.linear(duration: 1)
                            .repeatForever(autoreverses: false)
                    )
                    .offset(y: isAnimating ? -50 : 0)
                    .animation(
                        Animation.easeInOut(duration: 1.2)
                            .repeatForever(autoreverses: true)
                    )
            }
        }
        .onAppear {
            self.isAnimating = true
        }
    }
}


struct ShimmerAnimation_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            BirdLoadingAnimation()
//            ComplexLoadingAnimation()
        }
    }
}
