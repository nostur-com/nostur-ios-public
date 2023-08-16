//
//  FeedSettings+Hashtags.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/08/2023.
//

import SwiftUI

struct FeedSettings_Hashtags: View {
    @State public var hashtags:[String]
    public var onChange:(([String]) -> ())?
    var body: some View {
        List {
            ForEach(hashtags, id:\.self) { tag in
                Text(String(format:"#%@", tag))
            }
            .onDelete { index in
                hashtags.remove(atOffsets: index)
            }
        }
        .listStyle(.plain)
        .onChange(of: hashtags) { newHashtags in
            onChange?(newHashtags)
        }
    }
}

struct FeedSettings_Hashtags_Previews: PreviewProvider {
    static var previews: some View {
        FeedSettings_Hashtags(hashtags:["apple", "banana", "cherry"])
            .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
    }
}

func isHashtag(_ string: String) -> Bool {
    let hashtagPattern = "^#([A-Za-z0-9_]{1,139})$"
    return string.range(of: hashtagPattern, options: .regularExpression) != nil
}
