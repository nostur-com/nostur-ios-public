//
//  ProcessingStatus.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/03/2023.
//

import SwiftUI

struct ProcessingStatus: View {
    
    @State var message:String? = nil
    @State var dismissTask:Task<Void, Never>? = nil
    
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
        .onAppear {
            setTemporaryMessage("Checking for new items...")
        }
        .onReceive(receiveNotification(.listStatus)) { notification in
            let message = notification.object as? String
            setTemporaryMessage(message)
        }
    }
    func setTemporaryMessage(_ message:String?) {
        self.message = message
        self.dismissTask?.cancel()
        self.dismissTask = Task {
            // dismiss message after 2.1 seconds
            do {
                try await Task.sleep(nanoseconds: 2_100_000_000)
                withAnimation {
                    self.message = nil
                }
            } catch { }
        }
    }
}

struct ProcessingStatus_Previews: PreviewProvider {
    static var previews: some View {
        ProcessingStatus()
    }
}
