//
//  AnyStatus.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/04/2023.
//

import SwiftUI

typealias AnyStatusMessage = (String, String?)

struct AnyStatus: View {
    @Environment(\.theme) private var theme
    var filter: String?
    @State var message: AnyStatusMessage? = nil
    @State var dismissTask: Task<Void, Never>? = nil
    
    var body: some View {
        VStack {
            if let message {
                Text(message.0)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(theme.accent))
                    .clipShape(Capsule())
            }
            else {
                EmptyView()
            }
        }
        .onReceive(receiveNotification(.anyStatus)) { notification in
            let message = notification.object as! AnyStatusMessage
            if let filter = filter {
                guard filter == message.1 else { return }
                setTemporaryMessage(message)
            }
            else {
                setTemporaryMessage(message)
            }
        }
    }
    
    func setTemporaryMessage(_ message: AnyStatusMessage) {
        self.message = message
        self.dismissTask?.cancel()
        self.dismissTask = Task {
            // dismiss message after 2.1 seconds
            do {
                try await Task.sleep(nanoseconds: 5_100_000_000)
                withAnimation {
                    self.message = nil
                }
            } catch { }
        }
    }
}

struct AnyStatus_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            AnyStatus(filter: "Test")
            Button("test") {
                sendNotification(.anyStatus, ("This is a message", "Test"))
            }
        }
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}
