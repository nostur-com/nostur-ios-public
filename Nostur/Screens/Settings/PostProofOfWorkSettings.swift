import SwiftUI

struct PostProofOfWorkSettings: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @AppStorage(PostProofOfWork.secondsKey) private var savedSeconds = PostProofOfWork.savedSeconds()
    @AppStorage(PostProofOfWork.hashRateKey) private var hashRate = 0.0
    @AppStorage(PostProofOfWork.enabledForDMsKey) private var enabledForDMs = false
    @State private var isMeasuring = true

    private var seconds: Double { PostProofOfWork.clampedSeconds(savedSeconds) }

    private var timeSelection: Binding<Double> {
        Binding(get: { seconds }, set: { savedSeconds = $0 })
    }

    var body: some View {
        NXForm {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Time per post")
                        Spacer()
                        timeLabel(seconds)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityHidden(true)

                    Slider(value: timeSelection, in: PostProofOfWork.timeRange, step: 0.25) {
                        Text("Time per post")
                    } minimumValueLabel: {
                        Text("Off")
                    } maximumValueLabel: {
                        timeLabel(PostProofOfWork.timeRange.upperBound)
                    }
                    .accessibilityValue(timeLabel(seconds))
                }
                .disabled(seconds == 0 && hashRate == 0)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if let bits = PostProofOfWork.target(for: seconds, hashRate: hashRate) {
                        let estimate = pow(2, Double(bits)) / hashRate
                        let posts = PostProofOfWork.postsPerTimeout(target: bits, hashRate: hashRate)
                        Text("About \(estimate, format: .number.precision(.fractionLength(0...2))) sec per post · \(bits) bits")
                        if posts <= 10_000 {
                            let timeout = Int(PostProofOfWork.timeoutSeconds)
                            Text("About 1 in \(posts, format: .number.precision(.significantDigits(1...2))) posts might take longer than \(timeout) seconds to post.")
                        }
                    } else if isMeasuring {
                        Text("Estimating time…")
                    } else if hashRate == 0 {
                        Text("Couldn’t estimate the time. Reopen this screen to try again.")
                    } else {
                        Text("Some relays require Proof of Work to accept your posts.")
                    }
                }
            }
            Section {
                Toggle("Enable for DMs", isOn: $enabledForDMs)
                    .disabled(seconds == 0 || hashRate == 0)
            }
        }
        .navigationTitle("Proof of Work")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") { dismiss() }
            }
        }
        .background(theme.listBackground)
        .task {
            if savedSeconds != seconds { savedSeconds = seconds }
            if let measured = try? await PostProofOfWork.benchmark(), !Task.isCancelled {
                hashRate = measured
            }
            isMeasuring = false
        }
    }

    private func timeLabel(_ seconds: Double) -> Text {
        seconds == 0 ? Text("Off") : Text("\(seconds, format: .number.precision(.fractionLength(0...2))) sec")
    }
}
