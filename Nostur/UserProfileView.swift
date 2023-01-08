//
//  UserProfileView.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/01/2023.
//

import SwiftUI

struct UserProfileView: View {
    
    var user : User
    
    var body: some View {
        ZStack() {
            
            GeometryReader { geo in
                Image("bitcoinerrrrrHeaderDummy")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: 150)
                    .clipped()
            }
            
            HStack {
                VStack {
                    Image(user.profileImageName)
                        .resizable()
                        .frame(width:75, height:75)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white,lineWidth:4).shadow(radius: 10))
                        .offset(x: 10, y: 150-37.5)
                    Spacer()
                }
                Spacer()
            }
         
            VStack(alignment: .leading) {
                Rectangle().background(.clear).foregroundColor(.clear).frame(height:150) // Spacer to push content below header pic
                
                HStack(alignment:.top) {
                
                    Spacer()
                
                    Text("Following")
                        .frame(height: 30)
                        .padding(.horizontal, 25)
                    //.padding(.vertical, 10)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.primary)
                        .background(.clear)
                        .cornerRadius(20)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.primary, lineWidth: 1)
                        }
                    }
                
                Text("\(user.name)")
                
                Text("\(user.bio)")
            
                Text("Followed by ppl you know...")
                
                // Tweets here
                Text("Tweets").font(.headline).fontWeight(.heavy).padding(.vertical, 10)
                TweetView(tweet: Tweet())
                TweetView(tweet: Tweet())
                
                Spacer()
                
            }.padding(10)
            
            // tabbar
        
            Spacer()
        }.ignoresSafeArea()
        
        
//        }.ignoresSafeArea()
    }
}

struct UserProfileView_Previews: PreviewProvider {
    static var previews: some View {
        UserProfileView(user:DummyUsers().users()[1])
    }
}
