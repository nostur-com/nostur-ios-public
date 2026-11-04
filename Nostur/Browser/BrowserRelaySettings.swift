import CoreData

enum BrowserRelaySettings {
    /// Read on the owning context, asynchronously. This also sees unsaved auth
    /// toggles in relay settings, without consulting or waiting for relay sockets.
    @MainActor
    static func snapshot(in suppliedContext: NSManagedObjectContext? = nil) async -> [BrowserRelaySetting] {
        let managedContext = suppliedContext ?? DataProvider.shared().viewContext
        return await managedContext.perform {
            guard let relays = try? managedContext.fetch(CloudRelay.fetchRequest()) else { return [] }
            return relays.compactMap { relay in
                guard !relay.isDeleted, let url = relay.url_ else { return nil }
                return BrowserRelaySetting(url: url, auth: relay.auth)
            }
        }
    }
}
