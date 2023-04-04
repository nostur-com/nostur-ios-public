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
            VStack{
                HStack {
                    Text(title)
                    if let unread {
                        Text("\(unread)")
                            .font(.footnote)
                            .foregroundColor(.white)
                            .padding(.horizontal,6)
                            .background(Capsule().foregroundColor(.red))
                            .offset(x:-4, y: 0)
                            .opacity(unread > 0 ? 1 : 0)
                    }
                }
                Divider()
                    .frame(height: 4)
                    .background(Color("AccentColor"))
                    .opacity(selected ? 1 : 0.2)
            }
        }
//        .frame(minWidth: 100)
        
        
    }
}

struct TabButton_Previews: PreviewProvider {
    static var previews: some View {
        HStack {
            TabButton(action: {
                print("dede")
            }, title: "testing!")
            
            TabButton(action: {
                print("dede")
            }, title: "testing!", selected: true)
                      
        }
    }
}
