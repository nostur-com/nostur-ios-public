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
    
    var body: some View {
        Button { action() } label: {
            VStack{
                Text(title)
                Divider()
                    .frame(height: 4)
                    .background(.green)
                    .opacity(selected ? 1 : 0.2)
            }
        }
        .frame(minWidth: 100)
        
        
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
