//
//  ProcessingStatus.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/03/2023.
//

import SwiftUI

struct ProcessingStatus: View {
    
    @State var message:String? = "Processing new items..."
    
    var body: some View {
        VStack {
            if let message {
                Text(message)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.blue))
                    .clipShape(Capsule())
            }
            else {
                EmptyView()
            }
        }
        .onReceive(receiveNotification(.listStatus)) { notification in
            message = notification.object as? String
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(3)) {
                withAnimation {
                    self.message = nil
                }
            }
        }
    }
}

struct ProcessingStatus_Previews: PreviewProvider {
    static var previews: some View {
        ProcessingStatus()
    }
}
