//
//  ProcessingStatus.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/03/2023.
//

import SwiftUI

struct ProcessingStatus: View {
    @EnvironmentObject var theme:Theme
    @State var message:String? = nil
    @State var socketMessage:String? = nil
    @State var connectedMessage:String? = nil
    @State var dismissTask:Task<Void, Never>? = nil
    @State var dismissSocketTask:Task<Void, Never>? = nil
    @State var dismissConnectedTask:Task<Void, Never>? = nil
    
    var body: some View {
        VStack {
            if let message {
                Text(message)
                    .lineLimit(1)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(theme.accent))
                    .clipShape(Capsule())
            }
            if let socketMessage {
                Text(socketMessage)
                    .lineLimit(2)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.red))
                    .clipShape(Capsule())
            }
            if let connectedMessage {
                Text(connectedMessage)
                    .lineLimit(1)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.green))
                    .clipShape(Capsule())
            }
            else {
                EmptyView()
            }
        }
        .onAppear {
//            setTemporaryMessage("Checking for new items...")
        }
        .onReceive(receiveNotification(.listStatus)) { notification in
            let message = notification.object as? String
            setTemporaryMessage(message)
        }
        .onReceive(receiveNotification(.socketNotification)) { notification in
            let message = notification.object as? String
            setTemporarySocketMessage(message)
        }
        .onReceive(receiveNotification(.socketConnected)) { notification in
            let message = notification.object as? String
            setTemporaryConnectedMessage(message)
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
    
    func setTemporarySocketMessage(_ message:String?) {
        self.socketMessage = message
        self.dismissSocketTask?.cancel()
        self.dismissSocketTask = Task {
            // dismiss message after 2.1 seconds
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation {
                    self.socketMessage = nil
                }
            } catch { }
        }
    }
    
    func setTemporaryConnectedMessage(_ message:String?) {
        self.connectedMessage = message
        self.dismissConnectedTask?.cancel()
        self.dismissConnectedTask = Task {
            // dismiss message after 2.1 seconds
            do {
                try await Task.sleep(nanoseconds: 2_600_000_000)
                withAnimation {
                    self.connectedMessage = nil
                }
            } catch { }
        }
    }
}

struct ProcessingStatus_Previews: PreviewProvider {
    static var previews: some View {
        ProcessingStatus()
            .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}
