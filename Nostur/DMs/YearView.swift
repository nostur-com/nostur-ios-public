//
//  YearView.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/01/2026.
//

import SwiftUI

struct YearView: View {
    public let ourAccountPubkey: String
    @ObservedObject public var year: ConversationYear
    public var vm: ConversionVM
    
    var body: some View {
        // days
        ForEach(year.days) { day in
            DayView(ourAccountPubkey: ourAccountPubkey, day: day, vm: vm)
        }
        
        // year header
        Text(year.year)
            .fontWeightBold()
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 20)
    }
}
