//
//  MessageView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI

struct TweetView: View {
    let tweet: Tweet
    
    var body: some View {
        
        VStack(spacing:2) { // A TWEET
            
            if tweet.retweetedByName != "" {
                HStack { // retweet header
                    // Retweet icon
                    Image(systemName:"arrow.2.squarepath")
                        .font(.system(size: 12, weight: .heavy))
                    //                    .shadow(color: .gray, radius: 2, x: 3, y: 3)
                        .foregroundColor(.secondary)
                    //                    .scaleEffect(0.7)
                        .frame(maxWidth:50, alignment: .trailing)
                    Text("\(tweet.retweetedByName) Retweeted")
                        .font(
                            .system(size: 12)
                            .weight(.heavy)
                        )
                    //                    .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Retweeter name
                    
                }.padding(.leading, 10)
            }
            
            VStack (alignment: .leading) { // Vstack for retweeted thread
                HStack(alignment: .top) { // Tweet
                    NavigationLink(value: tweet, label: {
                        VStack { // profile image + thread line
                            // profile image
                            NavigationLink(value:tweet.user, label: {
                                if (true) {
                                    Circle().foregroundColor(randomColor(seed: tweet.name)).frame(maxWidth:50, maxHeight:50)
                                }
                                else {
                                    Image(tweet.profileImageName).resizable().scaledToFit()
                                        .clipShape(Circle())
                                        .shadow(color: .gray, radius: 1.0)
                                        .frame(maxWidth:50, maxHeight:50)
                                }
                            })
                            // thread line
                            if tweet.hasThread {
                                HStack {
//                                    Spacer()
//                                    Rectangle().frame(width:1, height:.infinity)
//                                        .foregroundColor(.gray)
//                                    Spacer()
                                }.frame(maxWidth: 50)
                            }
                            else {
//                                Spacer()
                            }
                            
                        }.padding(.leading, 10)
                    })
                
                    
                    
                    VStack(alignment: .leading, spacing: 3) { // Tweet container
                        HStack { // name + reply + context menu
                            
                            NavigationLink(value:tweet, label: {
                                VStack(alignment: .leading) { // Name + menu "replying to"
                                    HStack(spacing:2) {
                                        Text(tweet.name) // Name
                                            .font(.system(size: 14))
                                            .foregroundColor(.primary)
                                            .fontWeight(.bold)
                                        
                                        if tweet.isVerified { // Verification check
                                            Image(systemName: "checkmark.seal.fill")
                                                .foregroundColor(.blue)
                                                .font(.system(size: 13))
                                        }
                                        
                                        Text("@\(tweet.username) · \(tweet.ago)") // Username + ago
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if (tweet.replyToUsername != "") {
                                        Text("Replying to @\(tweet.replyToUsername)")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 13))
                                            .fontWeight(.light)
                                    }
                                }
                            })
                            
                            Spacer()
                            
                            Menu {
                                Button {
                                    print("Unfollow @\(tweet.username)")
                                } label: {
                                    Label("Unfollow @\(tweet.username)", systemImage: "person.fill.xmark")
                                }
                                Button {
                                    print("Block @\(tweet.username)")
                                } label: {
                                    Label("Block @\(tweet.username)", systemImage: "slash.circle")
                                }
                            } label: {
                                Text("···")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 0)
                                    .padding(.bottom, 10)
                                    .padding(.leading, 20)
                                    .padding(.trailing, 10)
                                
                            }
                        }
                   
                        NavigationLink(value:tweet, label: {
                            Text(tweet.text).multilineTextAlignment(TextAlignment.leading)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        })
                        
                        if tweet.hasImage {
                            Image(tweet.imageName)
                                .resizable()
                                .cornerRadius(10)
                                .aspectRatio(contentMode: .fit)
                                .padding(.vertical, 10)
                        }
                        
                        HStack { // Footer stats
                            Button(action: {
                                // Handle retweet action
                            }) {
                                HStack {
                                    Image(systemName: "message")
                                    Text("\(tweet.replyCount)")
                                }.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
                            }
                            
                            
                            Button(action: {
                                // Handle retweet action
                            }) {
                                HStack {
                                    Image(systemName: "arrow.2.squarepath")
                                    Text("\(tweet.retweetCount)")
                                }.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
                            }
                            
                            Button(action: {
                                // Handle like action
                            }) {
                                HStack {
                                    Image(systemName: "heart")
                                    Text("\(tweet.likeCount)")
                                }.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
                            }
                        }.foregroundColor(.gray)
                            .padding(.top, 3)
                    }.padding(.trailing, 10).padding(.bottom, 5)
                }
                if tweet.hasThread {
                    HStack { // "Show this thread"
                        ZStack {
                            Rectangle().frame(maxWidth: 50, maxHeight: 25).foregroundColor(.clear)
                            Image(tweet.profileImageName).resizable().scaledToFit()
                                .clipShape(Circle())
                                .shadow(color: .gray, radius: 1.0)
                                .frame(maxWidth:25, maxHeight:25)
                        }.padding(.leading, 10)
                        Text("Show this thread").font(.system(size: 14))
                    }
                }
            }
            .navigationDestination(for: Tweet.self) { tweet in
                MessageDetailView(tweet: tweet)
            }
            .navigationDestination(for: User.self) { user in
                UserProfileView(user:user)
            }
            Divider()
        }
    }

    func randomColor(seed: String) -> Color {
        
        var total: Int = 0
        for u in seed.unicodeScalars {
            total += Int(UInt32(u))
        }
        
        srand48(total * 200)
        let r = CGFloat(drand48())
        
        srand48(total)
        let g = CGFloat(drand48())
        
        srand48(total / 200)
        let b = CGFloat(drand48())
        
        return Color(cgColor: CGColor(red: r, green: g, blue: b, alpha: 0.7))
    }
    
}

struct TweetView_Previews: PreviewProvider {
    static var previews: some View {
        TweetView(tweet: Tweet(hasThread: true))
    }
}
