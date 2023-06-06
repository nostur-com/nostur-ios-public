import Foundation

extension Event {
    var privateNote:PrivateNote? {
        guard let account = NosturState.shared.account else { return nil }
        return account.privateNotes_.first(where: { $0.post == self })
    }
}
