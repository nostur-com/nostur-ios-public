//
//  DayView.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/12/2025.
//

import SwiftUI

struct DayView: View {
    public let ourAccountPubkey: String
    @ObservedObject public var day: ConversationDay
    public var vm: ConversionVM
    
    var body: some View {
        // messages
        VStack {
            ForEach(day.messages) { message in
                BalloonView17(nrChatMessage: message, accountPubkey: ourAccountPubkey, vm: vm)
                    .id(message.id)
            }
        }
        
        // day header
        Text(day.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
            .fontWeightBold()
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 20)
    }
}
