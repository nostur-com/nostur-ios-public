//
//  NosturStyles.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/02/2023.
//

import Foundation
import SwiftUI

struct NosturButton: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    public var height: CGFloat = 30
    public var bgColor: Color = Color.secondary

    func makeBody(configuration: Configuration) -> some View {        
        
        configuration.label
            .lineLimit(1)
            .frame(height: height)
            .padding(.horizontal, 10)
            .font(.caption.weight(.heavy))
            .foregroundColor(Color.white)
            .background(bgColor)
            .cornerRadius(15)
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(bgColor, lineWidth: 1)
            }
    }
}

struct FollowButtonInner: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    
    public var isFollowing: Bool = false
    public var isPrivateFollowing:Bool = false
    
    private var buttonText: String {
        if (isFollowing && isPrivateFollowing) {
            return String(localized: "🤫 Following", comment: "Follow/Unfollow button when the state is 'Following silent'")
        }
        else if isFollowing {
            return String(localized: "Following", comment: "Follow/Unfollow button when the state is 'Following'")
        }
        else {
            return String(localized: "Follow", comment: "Button to follow someone")
        }
    }
    
    var body: some View {
        
        let whiteColor = colorScheme == .light ? Color.white : Color.black
        let blackColor = colorScheme == .light ? Color.black : Color.white
        
        Text(buttonText)
            .lineLimit(1)
            .frame(width: 105, height: 30)
//            .padding(.horizontal, 25)
            .font(.caption.weight(.heavy))
            .foregroundColor(isFollowing ? blackColor : whiteColor)
            .background(isFollowing ? whiteColor : blackColor)
            .cornerRadius(20)
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(.gray, lineWidth: 1)
            }
            .opacity(isEnabled ? 1.0 : 0.3)
    }
}


struct FollowButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            FollowButton(pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e")
        }
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}
