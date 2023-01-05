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
            Tweet(text: "The stronger than expected #ADP jobs report is indicative of a weak, not a stong #labor market. In strong labor markets #inflation doesn't force workers who already have full-time jobs to take 2nd or 3rd low-paying, part-time jobs to make ends meet. Rate hikes will make it worse.", hasImage: false, isVerified: true, imageName: "", username: "PeterSchiff", name: "Peter Schiff", profileImageName: "peterschiffDummy", retweetCount: "28", likeCount: "189", replyCount: "8", retweetedByName: "", replyToUsername: "", ago: "1m", hasThread: false),
            Tweet(retweetedByName: "Stephan Livera", replyToUsername: "PaulREhrlich"),
            Tweet(text: "Een mens op een fiets is belachelijk efficient. Wat een mooie grafiek!\n\n(1/4)", hasImage: false, isVerified: false, imageName: "", username: "bslagter", name: "Bert Slagter", profileImageName: "bslagterDummy", retweetCount: "8", likeCount: "64", replyCount: "1", retweetedByName: "", replyToUsername: "", ago: "4m", hasThread: true),
            Tweet(text: "Treasury & Fed conducted a “chicken pivot” in 4q22 post-IMF meeting in mid-October.  IMO it is unclear how sustainable it is.\nIs QE returning by stealth? | Financial Times", hasImage: false, isVerified: true, imageName: "", username: "LukeGromen", name: "Luke Gromen", profileImageName: "lukegromenDummy", retweetCount: "19", likeCount: "89", replyCount: "7", retweetedByName: "", replyToUsername: "", ago: "30m", hasThread: false),
            Tweet(text: "Refrigeration has trade-offs. Everything, as a rule, has trade-offs.\nIt is behind the increase of saturated fats (meats & bovine dairy) in the consumption of Mediterraneans. Olive oil requires no refrigeration.", hasImage: false, isVerified: true, imageName: "", username: "nntaleb", name: "Nassim Nicholas Taleb", profileImageName: "nntalebDummy", retweetCount: "307", likeCount: "653", replyCount: "7", retweetedByName: "", replyToUsername: "", ago: "2h", hasThread: false),
            Tweet(text: "UPDATE: DCG/Genesis is under active investigation by the SEC.\n\n**sources confirmed that there are multiple whisleblowers that have come forward.", isVerified: true, username: "AP_Abacus", name: "André Neves", profileImageName: "andrenevesDummy", retweetCount: "105", likeCount: "2.286", replyCount: "105", hasThread: false)
            ]
    }
}

struct Tweet : Identifiable {
    let id = UUID()
    
    var text = "The fact that your work passes peer review is perhaps the best possible argument against peer review being even a marginally beneficial or conclusive measurement of accuracy"
    var hasImage = false
    var isVerified = false
    var imageName = ""
    var username = "Fabian_NL"
    var name = "Fabian"
    var profileImageName = "NosturAppIcon"
    var retweetCount = "5.791"
    var likeCount = "40,9K"
    var replyCount = "1.028"
    var retweetedByName = ""
    var replyToUsername = ""
    var ago = "1h"
    
    // Retweet with thread
    var hasThread : Bool = false
}

struct DummyData_Previews: PreviewProvider {
    static var previews: some View {
        TimelineView(tweets:DummyTweets().tweets())
    }
}
