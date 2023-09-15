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

    func makeBody(configuration: Configuration) -> some View {        
        
        configuration.label
            .lineLimit(1)
            .frame(height: 30)
            .padding(.horizontal, 15)
            .font(.caption.weight(.heavy))
            .foregroundColor(Color.white)
            .background(Color.secondary)
            .cornerRadius(20)
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(.gray, lineWidth: 1)
            }
    }
}

struct FollowButton: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) var colorScheme
    var isFollowing: Bool = false
    var isPrivateFollowing:Bool = false
    
    var buttonText:String {
        if (isFollowing && isPrivateFollowing) {
            return String(localized:"🤫 Following", comment:"Follow/Unfollow button when the state is 'Following silent'")
        }
        else if isFollowing {
            return String(localized:"Following", comment:"Follow/Unfollow button when the state is 'Following'")
        }
        else {
            return String(localized:"Follow", comment:"Button to follow someone")
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
            FollowButton(isFollowing: false, isPrivateFollowing: false)
            FollowButton(isFollowing: false, isPrivateFollowing: false)
                .disabled(true)
            
            FollowButton(isFollowing: true, isPrivateFollowing: false)
            FollowButton(isFollowing: true, isPrivateFollowing: false)
                .disabled(true)
            
            FollowButton(isFollowing: true, isPrivateFollowing: true)
            FollowButton(isFollowing: true, isPrivateFollowing: true)
                .disabled(true)
        }
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}
