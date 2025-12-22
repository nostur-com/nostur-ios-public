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
        // day header
        Text(day.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
            .fontWeightBold()
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 20)
        
        // messagess
        ForEach(day.messages) { message in
            BalloonView17(nrChatMessage: message, accountPubkey: ourAccountPubkey, vm: vm)
                .id(message.id)
        }
    }
}
