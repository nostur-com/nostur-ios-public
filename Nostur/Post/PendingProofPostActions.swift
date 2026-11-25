import SwiftUI

struct PendingProofPostActions: View {
    @ObservedObject private var outbox = PostProofOfWorkOutbox.shared
    @Environment(\.theme) private var theme
    let id: UUID

    var body: some View {
        HStack {
            if let post = outbox.posts.first(where: { $0.id == id }) {
                switch post.status {
                case .preparing:
                    Text("Adding Proof of Work…")
                case .signing:
                    Text("Signing post...")
                case .ready:
                    Text("Sending post...")
                }
                Spacer(minLength: 4)
                Button("Send Now") { outbox.sendNow(id) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(post.status == .ready ? theme.accent : Color.secondary)
                    .disabled(post.status != .ready)
                Button("Undo") { outbox.undo(id) }
                    .buttonStyle(NRButtonStyle(style: .borderedProminent))
                    .foregroundColor(.white)
            } else {
                Text("Sending post...")
                Spacer()
            }
        }
        .font(.footnote)
    }
}

struct PostPreparationFailureAlert: View {
    @ObservedObject private var outbox = PostProofOfWorkOutbox.shared

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .alert("Post wasn’t sent", isPresented: $outbox.showsFailure) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Nostur couldn’t finish preparing this post. Your draft was saved.")
            }
    }
}
