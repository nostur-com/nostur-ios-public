//
//  TabButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/02/2023.
//

import SwiftUI

struct TabButton: View {
    
    var action:() -> Void
    var title:String = ""
    var selected:Bool = false
    var unread:Int?
    
    var body: some View {
        Button { action() } label: {
            VStack(spacing:8) {
                HStack {
                    Text(title).lineLimit(1)
                        .opacity(selected ? 1 : 0.75)
                        .padding(.horizontal, 2)
                    if let unread, unread > 0 {
                        Text("\(unread)")
                            .font(.footnote)
                            .foregroundColor(.white)
                            .padding(.horizontal,6)
                            .background(Capsule().foregroundColor(.red))
                            .offset(x:-4, y: 0)
                    }
                }
                Divider()
                    .frame(height: 3)
                    .background(Color("AccentColor"))
                    .opacity(selected ? 1 : 0.35)
            }
            .contentShape(Rectangle())
        }
//        .frame(minWidth: 100)
        
        
    }
}

struct TabButton_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 4) {
            TabButton(action: {
                print("dede")
            }, title: "testing!")
            
            TabButton(action: {
                print("dede")
            }, title: "testing!")
            
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
    }
}
