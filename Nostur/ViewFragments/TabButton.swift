//
//  TabButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/02/2023.
//

import SwiftUI

struct TabButton: View {
    @EnvironmentObject private var themes:Themes
    var action:() -> Void
    var title:String = ""
    var secondaryText:String? = nil
    var selected:Bool = false
    var unread:Int?
    var muted:Bool = false
    
    var body: some View {
        Button { action() } label: {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 3) {
                    Text(title).lineLimit(1)
//                        .layoutPriority(1)
                        .foregroundColor(themes.theme.accent)
//                        .frame(maxWidth: .infinity)
                        
                    if let secondaryText {
                        Text(secondaryText).lineLimit(1)
                            .font(.caption)
                            .foregroundColor(themes.theme.accent.opacity(0.5))
//                            .frame(maxWidth: .infinity)
                        
                    }
                    if let unread, unread > 0 {
                        Text("\(unread)")
                            .font(.footnote)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .background(Capsule().foregroundColor(themes.theme.badge))
                            .opacity(muted ? 0.25 : 1.0)
                            .offset(y: -2)
                    }
                }
                .padding(.bottom, 5)
                .padding(.top, 8)
                .fixedSize()
                themes.theme.accent
                    .frame(height: 3)
                    .opacity(selected ? 1 : 0.15)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
    }
}

#Preview("Tab buttons") {
    PreviewContainer {
        VStack(spacing: 0) {
            
            // MANY TABS
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing:0) {
                    Group {
                        TabButton(action: {
                            print("dede")
                        }, title: "Following", selected:true)
                        Spacer()
                        
                        TabButton(action: {
                            print("dede")
                        }, title: "Quality")
                        Spacer()
                        
                        TabButton(action: {
                            print("dede")
                        }, title: "Hot", secondaryText: "4h")
                        Spacer()
                        
                        TabButton(action: {
                            print("dede")
                        }, title: "Gallery")
                        Spacer()
                    }
                    Group {
                        TabButton(action: {
                            print("dede")
                        }, title: "Explore")
                        Spacer()
                        
                        TabButton(action: {
                            print("dede")
                        }, title: "Articles")
                        Spacer()
                        
                        TabButton(action: {
                            print("dede")
                        }, title: "Popular")
                    }
                }
                .padding(.horizontal, 10)
                .frame(minWidth: UIScreen.main.bounds.width)
            }
            
            Divider()
            
            // LESS TABS
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing:0) {
                    TabButton(action: {
                        print("dede")
                    }, title: "Following")

                    Spacer()

                    TabButton(action: {
                        print("dede")
                    }, title: "Explore")
                }
                .padding(.horizontal, 10)
                .frame(minWidth: UIScreen.main.bounds.width)
            }
            

            Divider()
            
            // NO SPACERS
            HStack(spacing: 2) {
                TabButton(action: {
                    print("dede")
                }, title: "Following")
                
                TabButton(action: {
                    print("dede")
                }, title: "Hot", secondaryText: "4h")
                
                TabButton(action: {
                    print("dede")
                }, title: "Globalish", unread:3)
                
                TabButton(action: {
                    print("dede")
                }, title: "testing!", selected: true)
            }
            .padding(.horizontal, 10)
            .frame(minWidth: UIScreen.main.bounds.width)
        }
        .frame(width: UIScreen.main.bounds.width)
        .onAppear {
            Themes.default.loadPink()
        }
    }
}
