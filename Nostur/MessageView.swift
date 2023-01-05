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
        
        //TwitterChirp, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        
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
                    
                }
            }
            
            VStack (alignment: .leading) { // Vstack for retweeted thread
                HStack { // Tweet
                    VStack { // profile image + thread line
                        // profile image
                        Image(tweet.profileImageName).resizable().scaledToFit()
                            .clipShape(Circle())
                            .shadow(color: .red, radius: 2.0)
                            .frame(maxWidth:50, maxHeight:50)
                        // thread line
                        if tweet.hasThread {
                            HStack {
                                Spacer()
                                Rectangle().frame(width:1, height: .infinity)
                                    .foregroundColor(.gray)
                                Spacer()
                            }.frame(maxWidth: 50)
                        }
                        else {
                            Spacer()
                        }

                    }.padding(.leading, 10)
                    
                    VStack(alignment: .leading, spacing: 3) { // Tweet container
                        HStack { // name + reply
                            
                            
                            VStack(alignment: .leading) { // Name + menu "replying to"
                                HStack(spacing:2) {
                                    Text(tweet.name) // Name
                                        .font(.system(size: 14))
                                        .fontWeight(.bold)
                                    
                                    if tweet.isVerified { // Verification check
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundColor(.blue)
                                            .font(.system(size: 13))
                                    }
                                    
                                    Text("@\(tweet.username) · \(tweet.ago)") // Username + ago
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Text("···")
                                        .foregroundColor(.secondary)
                                        .padding(.trailing, 10)
                                }
                                
                                if (tweet.replyToUsername != "") {
                                    Text("Replying to @\(tweet.replyToUsername)")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 13))
                                        .fontWeight(.light)
                                }
                            }
                        }//.border(Color.gray.opacity(0.2), width: 1)
                        
                        //TwitterChirp, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                        Text(tweet.text)
                            .font(.system(size: 14))
                        
                        if tweet.hasImage {
                            Image(tweet.imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
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
                                    .shadow(color: .red, radius: 2.0)
                                    .frame(maxWidth:25, maxHeight:25)
                        }.padding(.leading, 10)
                        Text("Show this thread").font(.system(size: 14))
                    }
                }
            }
            Divider()
        }
    }
}

struct MessageView: View {
    
    var tweet = Tweet()
    
    var body: some View {
        
        ZStack {
//            Rectangle().foregroundColor(.gray)
            VStack {
                TweetView(tweet:tweet)
                //            HStack {
                //                Image(systemName: "person.crop.circle").resizable()
                //                    .scaledToFit()
                //                    .frame(maxWidth: 50)
                //                Text("Tweeet\nfsdfsfsf fdsf dsfsdfd fsdf\nsdfds").frame(alignment: .leading).multilineTextAlignment(TextAlignment.leading)
                //                Spacer()
                //            }
            }.frame(alignment: .leading)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 50, maxHeight: .infinity)
//                .border(Color.gray.opacity(0.2), width: 1)
//                .cornerRadius(2)
        }//.border(.purple)
        
        
    }
}

struct MessageView_Previews: PreviewProvider {
    static var previews: some View {
//        LazyVStack {
//            MessageView()
//            MessageView()
//            MessageView(tweet:Tweet(hasThread: false))
//        }.padding(.vertical)
        TimelineView(tweets:DummyTweets().tweets())
    }
}
