import SwiftUI

struct PostProofOfWorkSettings: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @AppStorage(PostProofOfWork.enabledKey) private var enabled = false
    @AppStorage(PostProofOfWork.secondsKey) private var savedSeconds = PostProofOfWork.defaultSeconds
    @AppStorage(PostProofOfWork.hashRateKey) private var hashRate = 0.0
    @State private var isMeasuring = true

    private var seconds: Double { PostProofOfWork.clampedSeconds(savedSeconds) }

    private var timeSelection: Binding<Double> {
        Binding(get: { seconds }, set: { savedSeconds = $0 })
    }

    var body: some View {
        NXForm {
            Section {
                Toggle("Add Proof of Work", isOn: $enabled)
                    .disabled(isMeasuring && hashRate == 0)
            } footer: {
                Text("Some relays require this to accept your posts.")
            }

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
                        timeLabel(PostProofOfWork.timeRange.lowerBound)
                    } maximumValueLabel: {
                        timeLabel(PostProofOfWork.timeRange.upperBound)
                    }
                    .accessibilityValue(timeLabel(seconds))
                }
                .disabled(!enabled)
            } footer: {
                if isMeasuring {
                    Text("Estimating time…")
                } else if let bits = PostProofOfWork.target(for: seconds, hashRate: hashRate) {
                    let estimate = pow(2, Double(bits)) / hashRate
                    Text("About \(estimate, format: .number.precision(.fractionLength(0...2))) sec per post · \(bits) bits")
                } else {
                    Text("Couldn’t estimate the time. Reopen this screen to try again.")
                }
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
        Text("\(seconds, format: .number.precision(.fractionLength(0...2))) sec")
    }
}
