////
////  DetailContainer.swift
////  Nostur
////
////  Created by Fabian Lachman on 24/02/2023.
////
//
//import SwiftUI
//
//struct DetailContainer: View {
//    @State var offsetX = 200.0
//    var body: some View {
//        ZStack {            
//            VStack{
//                Spacer()
//                HStack {
//                    Spacer()
//                    Image("NosturLogoFull")
//                        .resizable()
//                        .opacity(0.3)
//                        .frame(width: 700, height: 700)
//                        .offset(x:offsetX, y:50)
//                        .onAppear {
//                            withAnimation(.easeOut(duration: 7.5)) {
//                                offsetX = 150
//                            }
//                        }
//                }
//            }
//        }
//    }
//}
//
//struct DetailContainer_Previews: PreviewProvider {
//    static var previews: some View {
//        DetailContainer()
//    }
//}
