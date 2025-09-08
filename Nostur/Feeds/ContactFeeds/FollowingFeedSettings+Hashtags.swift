//
//  FeedSettings+Hashtags.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/08/2023.
//

import SwiftUI

struct FollowingFeedSettings_Hashtags: View {
    @Environment(\.theme) private var theme
    @State public var hashtags: [String]
    public var onChange: (([String]) -> ())?
    var body: some View {
        LazyVStack(alignment: .leading) {
            ForEach(hashtags.indices, id:\.self) { index in
                VStack(alignment: .leading) {
                    HStack {
                        Text(String(format: "#%@", hashtags[index]))
                        Spacer()
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                            .onTapGesture {
                                hashtags.remove(at: index)
                            }
                    }
                    if hashtags[index] != hashtags.last {
                        Divider()
                    }
                }
            }
        }
        .onChange(of: hashtags) { newHashtags in
            onChange?(newHashtags)
        }
    }
}

#Preview {
    Form {
        FollowingFeedSettings_Hashtags(hashtags: ["apple", "banana", "cherry"])
    }
}

func isHashtag(_ string: String) -> Bool {
    let hashtagPattern = "^#([A-Za-z0-9_]{1,139})$"
    return string.range(of: hashtagPattern, options: .regularExpression) != nil
}
