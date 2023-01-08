//
//  MessageDetailView.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/01/2023.
//

import SwiftUI

struct MessageDetailView: View {
    var tweet : Tweet
    
    var body: some View {
        VStack {
            // Parent Tweet
            
            
            VStack {
                // Retweeted header
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
                
                HStack {
                    // profile image
                    Image(tweet.profileImageName).resizable().scaledToFit()
                        .clipShape(Circle())
                        .shadow(color: .gray, radius: 1.0)
                        .frame(maxWidth:50, maxHeight:50)
                    // name and username
                    
                    HStack {
                        VStack {
                            
                            HStack(spacing:2) {
                                Text(tweet.name) // Name
                                    .font(.system(size: 14))
                                    .fontWeight(.bold)
                                
                                if tweet.isVerified { // Verification check
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 13))
                                }
                                Spacer()
                            }
                            
                            HStack {
                                Text("@\(tweet.username)") // Username
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            
                        }//.border(.red)
                    }
                    
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
                // "Replying to"
                if (tweet.replyToUsername != "") {
                    HStack {
                        Text("Replying to @\(tweet.replyToUsername)")//.border(.red)
                        Spacer()
                    }
                }
                // Tweet
                HStack {
                    Text(tweet.text)
                        .font(.system(size: 18))//.border(.red)
                    Spacer()
                }.padding(.vertical,5)
            }.padding(10)
            
            
            Divider()

            // Footer
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
                    }.frame(maxWidth: .infinity, alignment: .center).font(.system(size: 14))
                }
                
                Button(action: {
                    // Handle like action
                }) {
                    HStack {
                        Image(systemName: "heart")
                        Text("\(tweet.likeCount)")
                    }.frame(maxWidth: .infinity, alignment: .trailing).font(.system(size: 14))
                }
            }.foregroundColor(.gray)
                .padding(10)
            
            // Replies
            LazyVStack {
                ForEach (tweet.replies ?? []) { tweet in
                    TweetView(tweet: tweet)
                }
            }
            
            // Finished
            Spacer()
        }
    }
}

struct MessageDetailView_Previews: PreviewProvider {
    static var previews: some View {
        MessageDetailView(tweet:DummyTweets().tweets()[6])
    }
}
