//
//  AppView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI

struct AppView: View {
    var screenWidth = UIScreen.main.bounds.width
    @State var xOffset: CGFloat = 0
    @State var currentXOffset: CGFloat = 0
    @Binding var showMenu:Bool
    @Environment(\.colorScheme) var scheme
    
    var body: some View {
        GeometryReader { reader in
            HStack(spacing: 0) {
                MenuView().frame(width: screenWidth * 0.8)
                
                ZStack {
                    Rectangle()
                        .foregroundColor(.white)
//                        .overlay(Text("placeholder"))
                        .frame(width: screenWidth)
                    
                    (scheme == .light ? Color.black : Color.white).opacity(0.3)
                      .opacity(0.3)
                        .opacity(xOffset == 0 ? 0.7 : 0)
                        .ignoresSafeArea()
                }
            }
            .onAppear {
                if (!showMenu) {
                    xOffset = -screenWidth * 0.8 // hides the menu
                    currentXOffset = xOffset
                }
                else {
                    xOffset = 0
                    currentXOffset = 0
                }
            }
            .offset(x: xOffset)
            .gesture(
                DragGesture()
                    .onChanged({ value in
                        if value.translation.width > 0 && xOffset != 0 { // left to right
                            withAnimation {
                                xOffset = currentXOffset + value.translation.width
                            }
                        } else if value.translation.width < 0 && xOffset != -screenWidth * 0.8 {
                            withAnimation {
                                xOffset = currentXOffset + value.translation.width
                            }
                        }
                    })
                    .onEnded({ value in
                        if value.translation.width > 0 { // left to right
                            withAnimation {
                                xOffset = 0
                            }
                        } else {
                            withAnimation {
                                xOffset = -screenWidth * 0.8
                            }
                        }
                        currentXOffset = xOffset
                    })
            )
        }
    }
}

struct MenuView: View {
    
    @Environment(\.colorScheme) var scheme
    @EnvironmentObject var ns:NosturState
    
    var followerCount = 1
    
    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                HStack(alignment: .top) {
                    ProfilePicView(pubkey: ns.account!.publicKey!, account: ns.account!)
                    
                    Spacer()
                    
                    Button(action: {}, label: {
                        Image(systemName: "ellipsis.circle")
                            .resizable()
                            .frame(width: 30, height: 30)
                            .foregroundColor(.accentColor)
                    })
                }
                
                Text("\(ns.account?.display_name ?? "Anon")")
                    .font(.system(size: 17, weight: .bold))
                
                Text("@\(ns.account?.name ?? "0000")")
                    .foregroundColor(.gray)
                
                HStack {
                    Text("780")
                        .fontWeight(.bold)
                    
                    Text("following")
                    
                    Text("\(followerCount)")
                        .fontWeight(.bold)
                        .padding(.leading)
                    
                    Text("followers")
                }
                .padding(.top)
            }
            .padding(.horizontal)
            
            ScrollView(.vertical, showsIndicators: false, content: {
                VStack(spacing: 0) {
                    ForEach(menuItems) { item in
                        Button(action: {}, label: {
                            HStack(spacing: 20) {
                                Image(systemName: item.image)
                                    .frame(width: 40, height: 40)
                                    .font(.system(size: 21, weight: .semibold))
                                    .foregroundColor(.primary)
                                
                                Text(LocalizedStringKey(item.name))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                            }
                            .padding()
                        })
                    }
                    
                    Divider()
                        .padding(.vertical)
                    
                    VStack(spacing: 30) {
                        Button(action: {}, label: {
                            HStack {
                                Text("Settings")
                                Spacer()
                            }
                        })
                        
                        Button(action: {}, label: {
                            HStack {
                                Text("Help") // if it doesn't work try cleaning the project
                                Spacer()
                            }
                        })
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 25)
                    Spacer()
                }
            })
            
            HStack {
                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                    Image(systemName: "lightbulb")
                })
                
                Spacer()
                
                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                    Image(systemName: "qrcode")
                })
            }
            .foregroundColor(.accentColor)
            .font(.system(size: 21))
            .padding()
        }
        .background((scheme == .dark ? Color.black : Color.white))
    }
}

struct MenuItem: Identifiable {
    let id = UUID().uuidString
    let image: String
    let name: String
}

let menuItems = [
    MenuItem(image: "person", name: "Profile"),
    MenuItem(image: "list.bullet.rectangle", name: "Lists"),
//    MenuItem(image: "text.bubble", name: "Topics"),
    MenuItem(image: "bookmark", name: "Bookmarks"),
//    MenuItem(image: "bolt", name: "moments"),
//    MenuItem(image: "star", name: "monetization")
]


struct AppView_Previews: PreviewProvider {
    @State static var showMenu = false
    
    static var previews: some View {
        AppView(showMenu: $showMenu)
            .withPreviewEnvironment()
    }
}
