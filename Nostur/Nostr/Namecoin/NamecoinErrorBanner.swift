//
//  NamecoinErrorBanner.swift
//  Nostur
//
//  Inline banner shown in the Search screen when a .bit / Namecoin
//  identifier lookup fails. Keeps the user informed about what went
//  wrong (name not found, servers unreachable, no nostr field, etc.)
//  instead of just silently showing an empty result list.
//

import SwiftUI

struct NamecoinErrorBanner: View {
    @Environment(\.theme) private var theme
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Namecoin lookup failed")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                )
        )
    }
}

/// Produce a short, user-facing sentence for a failed Namecoin outcome.
/// Success outcomes must be handled by the caller before this is called.
func namecoinErrorMessage(for outcome: NamecoinResolveOutcome, identifier: String) -> String? {
    switch outcome {
    case .success:
        return nil
    case .nameNotFound(let name):
        return "\"\(identifier)\" is not registered on Namecoin (queried \(name))."
    case .noNostrField(let name):
        return "\"\(identifier)\" is registered (\(name)) but has no \"nostr\" field in its Namecoin record."
    case .serversUnreachable(let msg):
        return "Could not reach any ElectrumX server. \(msg)"
    case .invalidIdentifier(let id):
        return "\"\(id)\" is not a valid .bit / d/ / id/ identifier."
    case .timeout:
        return "Namecoin lookup timed out. Check your connection and try again."
    }
}
