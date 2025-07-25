//
//  NestButtons.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/07/2024.
//

import SwiftUI

struct NestButtons: View {
    @Environment(\.theme) private var theme
    @ObservedObject public var liveKitVoiceSession: LiveKitVoiceSession
    
    var body: some View {
        HStack(alignment: .top) {
            VStack {
                Toggle("Mute mic", systemImage: liveKitVoiceSession.isMuted ? "mic.slash.fill" : "mic.fill", isOn: $liveKitVoiceSession.isMuted)
                    .font(.largeTitle)
                    .labelStyle(.iconOnly)
                    .toggleStyle(NestToggleStyle(theme: theme))
                
                Text(liveKitVoiceSession.isMuted ? "Mic is off" : "Mic is on")
            }
            
            Spacer()
            
            VStack {
                Toggle("Raise hand", systemImage: liveKitVoiceSession.raisedHand ? "hand.raised.fill" : "hand.raised", isOn: $liveKitVoiceSession.raisedHand)
                    .font(.largeTitle)
                    .labelStyle(.iconOnly)
                    .toggleStyle(NestToggleStyle(theme: theme))
                
                Text("Hand is raised")
                    .opacity(liveKitVoiceSession.raisedHand ? 1.0 : 0)
            }
        }
    }
}

#Preview {
    PreviewContainer {
        NestButtons(liveKitVoiceSession: LiveKitVoiceSession.shared)
    }
}


struct NestButtonStyle: ButtonStyle {
    var theme: Theme
    var style: Style = .default
    
    enum Style {
        case `default`
        case borderedProminent
    }
    
    func makeBody(configuration: Configuration) -> some View {
        MyButton(configuration: configuration, style: style)
    }
    
    struct MyButton: View {
        let configuration: ButtonStyle.Configuration
        var style: Style = .default
        @Environment(\.theme) private var theme
    
        @Environment(\.isEnabled) private var isEnabled: Bool
    
        var body: some View {
            switch style {
            case .default:
                configuration.label
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                           RoundedRectangle(cornerRadius: 25)
                            .stroke(theme.lineColor, lineWidth: 1)
                    )
                    .clipShape(.rect(cornerRadius: 25))
                    .foregroundColor(theme.accent)
                    .opacity(isEnabled ? 1.0 : 0.5)
            case .borderedProminent:
                configuration.label
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(theme.accent)
                    .clipShape(.rect(cornerRadius: 25))
                    .foregroundColor(Color.white)
                    .opacity(isEnabled ? 1.0 : 0.5)
            }
        }
    }
}

struct NestToggleStyle: ToggleStyle {
    var theme: Theme
    
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .accessibility(label: Text(configuration.isOn ? "Checked" : "Unchecked"))
                .foregroundStyle(configuration.isOn ? Color.white : .white)
                .padding(10)
                .background(theme.accent)
                .clipShape(.rect(cornerRadius: 25))
        }
        .buttonStyle(.plain)
    }
}
