//
//  DummyData.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import Foundation
import SwiftUI

struct DummyTweets {
    func tweets() -> Array<Tweet> {
        return [
            Tweet(retweetedByName: "Stephan Livera", replyToUsername: "PaulREhrlich"),
            Tweet(text: "2022 was a tough year for mega-cap tech companies as inflation cut consumer spending and interest rate hikes led to lower earnings. These six Big Tech companies lost a combined $4.7 trillion in market cap in the last 12 months. Do you think Big Tech will recover in 2023? 🤔", hasImage: true, isVerified: true, imageName: "imageDummy", username: "DEGIRO", name: "DEGIRO", profileImageName: "degiroDummy", retweetCount: "1", likeCount: "7", replyCount: "0", retweetedByName: "", replyToUsername: "", ago: "1m", hasThread: false),
            Tweet(text: "The stronger than expected #ADP jobs report is indicative of a weak, not a stong #labor market. In strong labor markets #inflation doesn't force workers who already have full-time jobs to take 2nd or 3rd low-paying, part-time jobs to make ends meet. Rate hikes will make it worse.", hasImage: false, isVerified: true, imageName: "", username: "PeterSchiff", name: "Peter Schiff", profileImageName: "peterschiffDummy", retweetCount: "28", likeCount: "189", replyCount: "8", retweetedByName: "", replyToUsername: "", ago: "1m", hasThread: false),
            Tweet(text: "Een mens op een fiets is belachelijk efficient. Wat een mooie grafiek!\n\n(1/4)", hasImage: false, isVerified: false, imageName: "", username: "bslagter", name: "Bert Slagter", profileImageName: "bslagterDummy", retweetCount: "8", likeCount: "64", replyCount: "1", retweetedByName: "", replyToUsername: "", ago: "4m", hasThread: true),
            Tweet(text: "Treasury & Fed conducted a “chicken pivot” in 4q22 post-IMF meeting in mid-October.  IMO it is unclear how sustainable it is.\nIs QE returning by stealth? | Financial Times", hasImage: false, isVerified: true, imageName: "", username: "LukeGromen", name: "Luke Gromen", profileImageName: "lukegromenDummy", retweetCount: "19", likeCount: "89", replyCount: "7", retweetedByName: "", replyToUsername: "", ago: "30m", hasThread: false),
            Tweet(text: "Refrigeration has trade-offs. Everything, as a rule, has trade-offs.\nIt is behind the increase of saturated fats (meats & bovine dairy) in the consumption of Mediterraneans. Olive oil requires no refrigeration.", hasImage: false, isVerified: true, imageName: "", username: "nntaleb", name: "Nassim Nicholas Taleb", profileImageName: "nntalebDummy", retweetCount: "307", likeCount: "653", replyCount: "7", retweetedByName: "", replyToUsername: "", ago: "2h", hasThread: false),
            Tweet(text: "UPDATE: DCG/Genesis is under active investigation by the SEC.\n\n**sources confirmed that there are multiple whisleblowers that have come forward.", isVerified: true, username: "AP_Abacus", name: "André Neves", profileImageName: "andrenevesDummy", retweetCount: "105", likeCount: "2.286", replyCount: "105", hasThread: true, replies: [
            Tweet(text: "The move comes as relations between Beijing and Canberra are thawing, and as China is trying to meet growing demand for coal because of higher power consumption following the easing of coronavirus-related restrictions.\nAustralia was China's second-largest coal supplier before the", replyToUsername: "AB_Abacus"),
            Tweet(text: "Very nice!", username: "PeterSchiff", name:"Peter Schiff", profileImageName: "peterschiffDummy", replyToUsername: "AB_Abacus")
            ])
            ]
    }
}

struct Tweet: Identifiable, Hashable {
    
    static func == (lhs: Tweet, rhs: Tweet) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
            hasher.combine(id)
    }
    
    let id = UUID()
    
    var text = "The fact that your work passes peer review is perhaps the best possible argument against peer review being even a marginally beneficial or conclusive measurement of accuracy"
    var hasImage = false
    var isVerified = false
    var imageName = ""
    var username = "Fabian_NL"
    var name = "Fabian"
    var profileImageName = "NosturAppIcon"
    var pictureUrl:String? = nil
    var pictureFile:Data? = nil
    var retweetCount = "5.791"
    var likeCount = "40,9K"
    var replyCount = "1.028"
    var retweetedByName = ""
    var replyToUsername = ""
    var ago = "1h"
    
    // Retweet with thread
    var hasThread : Bool = false
    
    var replies : Array<Tweet>?
    var user = DummyUsers().users()[0]
    var contact:Contact? = nil
}

struct User : Identifiable, Hashable {
    
    func hash(into hasher: inout Hasher) {
            hasher.combine(id)
    }
    
    let id = UUID()
    
    var bio = "Yes its good!"
    var isVerified = true
    var username = "Fabian_NL"
    var name = "Fabian"
    var profileImageName = "NosturAppIcon"
    var followerCount = "203"
    var following = "42"
    var tweets : Array<Tweet>?
}

struct DummyUsers {
    func users() -> Array<User> {
        return [
            User(),
            User(bio: "Yo", isVerified: true, username: "jackmallers", name: "Jack Mallers", profileImageName: "nntalebDummy", followerCount: "731K", following: "254", tweets: [])
        ]
    }
}
    
