//
//  TabButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/02/2023.
//

import SwiftUI

struct TabButton: View {
    @EnvironmentObject var theme:Theme
    var action:() -> Void
    var title:String = ""
    var secondaryText:String? = nil
    var selected:Bool = false
    var unread:Int?
    
    var body: some View {
        Button { action() } label: {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 3) {
                    Text(title).lineLimit(1)
//                        .layoutPriority(1)
                        .foregroundColor(theme.accent)
//                        .frame(maxWidth: .infinity)
                        
                    if let secondaryText {
                        Text(secondaryText).lineLimit(1)
//                            .font(.footnote)
                            .foregroundColor(theme.accent.opacity(0.5))
//                            .frame(maxWidth: .infinity)
                        
                    }
                    if let unread, unread > 0 {
                        Text("\(unread)")
                            .font(.footnote)
                            .foregroundColor(.white)
                            .padding(.horizontal,6)
                            .background(Capsule().foregroundColor(theme.badge))
                            .offset(y: -2)
                    }
                }
                .padding(.bottom, 5)
                .padding(.top, 8)
                theme.accent
                    .frame(height: 3)
                    .opacity(selected ? 1 : 0.15)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
    }
}

struct TabButton_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            VStack {
                HStack(spacing: 2) {
                    TabButton(action: {
                        print("dede")
                    }, title: "testing!")
                    
                    TabButton(action: {
                        print("dede")
                    }, title: "testing!", secondaryText: "4h")
                    
                    TabButton(action: {
                        print("dede")
                    }, title: "testing!", unread:3)
                    
                    TabButton(action: {
                        print("dede")
                    }, title: "testing!")
                    
                    TabButton(action: {
                        print("dede")
                    }, title: "testing!")
                    
                    TabButton(action: {
                        print("dede")
                    }, title: "testing!", selected: true)
                              
                }
                Divider()
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
            }
            .onAppear {
                Theme.default.loadPink()
            }
        }
    }
}
