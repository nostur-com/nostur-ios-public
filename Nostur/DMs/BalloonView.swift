//
//  BalloonView.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/03/2023.
//

import SwiftUI

struct BalloonView: View {
    @EnvironmentObject var themes: Themes
    var message: String
    var isSentByCurrentUser: Bool
    var time: String
    
    var renderedMessage:String {
        if message == "(Encrypted content)" {
            return convertToHieroglyphs(text: message)
        }
        return message
    }
    
    var body: some View {
        HStack {
            if isSentByCurrentUser {
                Spacer()
            }
            
            NRText(renderedMessage)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSentByCurrentUser ? themes.theme.background : themes.theme.listBackground)
                )
                .background(alignment: isSentByCurrentUser ? .bottomTrailing : .bottomLeading) {
                    Image(systemName: "moon.fill")
                        .foregroundColor(isSentByCurrentUser ? themes.theme.background : themes.theme.listBackground)
                        .scaleEffect(x: isSentByCurrentUser ? 1 : -1)
                        .rotationEffect(.degrees(isSentByCurrentUser ? 35 : -35))
                        .offset(x: isSentByCurrentUser ? 10 : -10, y: 0)
                        .font(.system(size: 25))
                }
                .padding(.horizontal, 10)
                .padding(isSentByCurrentUser ? .leading : .trailing, 50)
                .overlay(alignment: isSentByCurrentUser ? .bottomLeading : .bottomTrailing) {
                    Text(time)
                        .frame(alignment: isSentByCurrentUser ? .leading : .trailing)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                        .padding(isSentByCurrentUser ? .leading : .trailing, 19)
                }
            
            if !isSentByCurrentUser {
                Spacer()
            }
        }
    }
}

func convertToHieroglyphs(text: String) -> String {
    let hieroglyphs: [Character] =  ["𓀀", "𓀁", "𓀂", "𓀃", "𓀄", "𓀅", "𓀆", "𓀇", "𓀈", "𓀉", "𓀊", "𓀋", "𓀌",
                                     "𓀍", "𓀎", "𓀏", "𓀐", "𓀑", "𓀒", "𓀓", "𓀔", "𓀕", "𓀖", "𓀗", "𓀘", "𓀙",
                                     "𓀚", "𓀛", "𓀜", "𓀝", "𓀞", "𓀟", "𓀠", "𓀡", "𓀢", "𓀣", "𓀤", "𓀥", "𓀦",
                                     "𓀧", "𓀨", "𓀩", "𓀪", "𓀫", "𓀬", "𓀭", "𓀮", "𓀯", "𓀰", "𓀱", "𓀲", "𓀳",
                                     "𓀴", "𓀵", "𓀶", "𓀷", "𓀸", "𓀹", "𓀺", "𓀻", "𓀼", "𓀽", "𓀾", "𓀿", "𓁀",
                                     "𓁁", "𓁂", "𓁃", "𓁄", "𓁅", "𓁆", "𓁇", "𓁈", "𓁉", "𓁊", "𓁋", "𓁌", "𓁍",
                                     "𓁎", "𓁏", "𓁐", "𓁑", "𓁒", "𓁓", "𓁔", "𓁕", "𓁖", "𓁗", "𓁘", "𓁙", "𓁚",
                                     "𓁛", "𓁜", "𓁝", "𓁞", "𓁟", "𓁠", "𓁡", "𓁢", "𓁣", "𓁤", "𓁥", "𓁦", "𓁧",
                                     "𓁨", "𓁩", "𓁪", "𓁫", "𓁬", "𓁭", "𓁮", "𓁯", "𓁰"]
    let outputLength = Int.random(in: 7..<20)
    var outputString = ""
    
    for _ in 0..<outputLength {
        let randomIndex = Int.random(in: 0..<hieroglyphs.count)
        outputString.append(hieroglyphs[randomIndex])
    }
    
    return outputString
}

struct BalloonView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            BalloonView(message: "Some message \nLonger text blablabl still looks good \nanother line yeee", isSentByCurrentUser: true, time: Date.now.formatted(date: .omitted, time: .standard))
            BalloonView(message: "https://image.nostr.build/24ad61d249914f423a87440da3b49006963befcecd6517ef7689c4302b88bf78.jpg\nddsd", isSentByCurrentUser: true, time: Date.now.formatted(date: .omitted, time: .standard))
            BalloonView(message: "https://image.nostr.build/24ad61d249914f423a87440da3b49006963befcecd6517ef7689c4302b88bf78.jpg", isSentByCurrentUser: true, time: Date.now.formatted(date: .omitted, time: .standard))
            BalloonView(message: "Some message", isSentByCurrentUser: false, time: Date.now.formatted(date: .omitted, time: .standard))
            BalloonView(message: "Some message", isSentByCurrentUser: false, time: Date.now.formatted(date: .omitted, time: .standard))
            BalloonView(message: "Some message", isSentByCurrentUser: true, time: Date.now.formatted(date: .omitted, time: .standard))
            Spacer()
        }
        .environmentObject(Themes.default)
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}
