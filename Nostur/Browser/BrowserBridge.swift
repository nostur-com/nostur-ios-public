import Foundation
import WebKit

/// This is the entire web-to-native wire format. No account identifiers, native
/// selectors, paths, relay settings, credentials or key material are accepted.
struct BrowserBridgeRequest: Decodable {
    enum Method: String, Decodable { case getPublicKey, signEvent }
    let documentToken: String
    let method: Method
    let event: BrowserUnsignedEvent?

    private struct Field: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: Field.self)
        guard Set(fields.allKeys.map(\.stringValue)) == ["documentToken", "method", "event"] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid bridge fields"))
        }
        documentToken = try fields.decode(String.self, forKey: Field("documentToken"))
        method = try fields.decode(Method.self, forKey: Field("method"))
        event = try fields.decodeIfPresent(BrowserUnsignedEvent.self, forKey: Field("event"))
        if event != nil {
            let payload = try fields.nestedContainer(keyedBy: Field.self, forKey: Field("event"))
            guard Set(payload.allKeys.map(\.stringValue)) == ["created_at", "kind", "tags", "content"] else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid event fields"))
            }
        }
    }

    static func decode(_ body: Any) -> BrowserBridgeRequest? {
        guard let string = body as? String, string.utf8.count <= 1_048_576,
              let data = string.data(using: .utf8),
              let request = try? JSONDecoder().decode(Self.self, from: data),
              string.utf8.count <= BrowserSigningPolicy.maximumRequestBytes(for: request.event?.kind ?? 0),
              UUID(uuidString: request.documentToken) != nil,
              (request.method == .getPublicKey && request.event == nil)
                || (request.method == .signEvent && request.event != nil) else { return nil }
        return request
    }
}

struct BrowserRequestScope: Equatable, Sendable {
    let documentToken: String
    let origin: String
    let accountPubkey: String
}

/// The only event fields allowed back across the bridge, even if the native
/// event model or signer response later gains additional fields.
struct BrowserSignedEvent: Codable, Equatable, Sendable {
    let id: String
    let pubkey: String
    let created_at: Int64
    let kind: Int
    let tags: [[String]]
    let content: String
    let sig: String

    var unsigned: BrowserUnsignedEvent {
        BrowserUnsignedEvent(created_at: created_at, kind: kind, tags: tags, content: content)
    }

    func matches(_ event: BrowserUnsignedEvent, accountPubkey: String) -> Bool {
        pubkey == accountPubkey && unsigned == event
            && Self.isHex(pubkey, count: 64) && Self.isHex(id, count: 64) && Self.isHex(sig, count: 128)
    }

    static func isHex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

enum BrowserBridge {
    static let world = WKContentWorld.world(name: "NosturSignerTransport")
    static let appPendingLimit = 4
    static let relayPendingLimit = 32

    // Used in both content worlds for transport admission only. Native policy
    // remains authoritative for the relay setting, origin, account and payload.
    private static let relayAuthenticationPredicate = #"""
    event => {
      if (event?.kind !== 22242 || event.content !== '' || !Array.isArray(event.tags)
          || event.tags.length > 256 || !event.tags.every(tag => Array.isArray(tag) && tag.length > 0
            && tag.length <= 16 && tag.every(value => typeof value === 'string' && value.length <= 4096))) return false;
      if (event.tags.some(tag => ['url','u','domain','method','action','origin','client-origin'].includes(tag[0]))) return false;
      const relays = event.tags.filter(tag => tag[0] === 'relay');
      const challenges = event.tags.filter(tag => tag[0] === 'challenge');
      if (relays.length !== 1 || relays[0].length !== 2 || challenges.length !== 1
          || challenges[0].length !== 2 || !challenges[0][1]) return false;
      try {
        const url = new URL(relays[0][1]);
        return ['wss:','ws:'].includes(url.protocol) && !!url.hostname && !url.username && !url.password && !url.hash;
      } catch (_) { return false; }
    }
    """#

    static func install(in controller: WKUserContentController, handler: WKScriptMessageHandlerWithReply) {
        controller.addScriptMessageHandler(handler, contentWorld: world, name: "nostur")
        controller.addUserScript(WKUserScript(source: isolatedScript, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
        controller.addUserScript(WKUserScript(source: pageScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    /// Native code activates only the current committed document. The token is
    /// never exposed to page scripts or put into DOM messages.
    static func activate(_ view: WKWebView, token: String) {
        view.callAsyncJavaScript("globalThis.__nosturDocumentToken = token; globalThis.__nosturActivate?.(token);",
                                 arguments: ["token": token], in: nil, in: world) { _ in }
    }

    static let pageScript = #"""
    (() => {
      if (window.top !== window) return;
      const pending = new Map();
      const isRelayAuthentication = \#(relayAuthenticationPredicate);
      const post = window.postMessage.bind(window);
      let sequence = 0;
      window.addEventListener('message', event => {
        if (!event.isTrusted || event.source !== window || typeof event.data !== 'string' || event.data.length > 2097152) return;
        let reply;
        try { reply = JSON.parse(event.data); } catch (_) { return; }
        if (reply?.channel !== 'nostur.response.v1' || !pending.has(reply.id)) return;
        const request = pending.get(reply.id);
        pending.delete(reply.id);
        clearTimeout(request.timeout);
        if (reply.error) request.reject(new Error(reply.error));
        else request.resolve(reply.result);
      });
      const request = (method, event) => new Promise((resolve, reject) => {
        const relay = method === 'signEvent' && isRelayAuthentication(event);
        const count = [...pending.values()].filter(request => request.relay === relay).length;
        if (count >= (relay ? \#(relayPendingLimit) : \#(appPendingLimit))) {
          reject(new Error('Too many pending Nostur requests.')); return;
        }
        let payload = null;
        if (method === 'signEvent') {
          if (!event || !Number.isSafeInteger(event.created_at) || !Number.isInteger(event.kind)
              || event.kind < 0 || event.kind > 65535 || typeof event.content !== 'string'
              || event.content.length > 65536 || !Array.isArray(event.tags)
              || event.tags.length > ([3,10000].includes(event.kind) ? 10000 : 256)
              || !event.tags.every(tag => Array.isArray(tag) && tag.length > 0 && tag.length <= 16
                && tag.every(value => typeof value === 'string' && value.length <= 4096))) {
            reject(new Error('Invalid or oversized signing request.')); return;
          }
          payload = {created_at: event.created_at, kind: event.kind, tags: event.tags, content: event.content};
        }
        const id = String(++sequence);
        const message = JSON.stringify({channel: 'nostur.request.v1', id, method, event: payload});
        if (message.length > ([3,10000].includes(payload?.kind) ? 1048000 : 131000)) {
          reject(new Error('Signing request is too large.')); return;
        }
        const timeout = setTimeout(() => { pending.delete(id); reject(new Error('Nostur request timed out.')); }, 140000);
        pending.set(id, {resolve, reject, timeout, relay});
        post(message, window.location.origin);
      });
      const nostr = Object.freeze({
        getPublicKey: () => request('getPublicKey'),
        signEvent: event => request('signEvent', event)
      });
      Object.defineProperty(window, 'nostr', {value: nostr, writable: false, configurable: false});
      window.dispatchEvent(new Event('nostr:ready'));
    })();
    """#

    static let isolatedScript = #"""
    (() => {
      if (window.top !== window) return;
      const handler = window.webkit.messageHandlers.nostur;
      const post = window.postMessage.bind(window);
      const encoder = new TextEncoder();
      let token = globalThis.__nosturDocumentToken;
      let activate;
      const ready = new Promise(resolve => { activate = resolve; });
      globalThis.__nosturActivate = value => { token = value; activate(); };
      if (token) activate();
      const pending = new Map();
      const isRelayAuthentication = \#(relayAuthenticationPredicate);
      let minute = Date.now(), appCount = 0, relayCount = 0;
      window.addEventListener('message', async event => {
        if (!event.isTrusted || event.source !== window || event.origin !== window.location.origin
            || typeof event.data !== 'string' || event.data.length > 1048576) return;
        let request;
        try { request = JSON.parse(event.data); } catch (_) { return; }
        if (request?.channel !== 'nostur.request.v1' || typeof request.id !== 'string' || request.id.length > 64) return;
        const reply = (result, error) => post(JSON.stringify({channel: 'nostur.response.v1', id: request.id, result, error}), window.location.origin);
        const relay = request.method === 'signEvent' && isRelayAuthentication(request.event);
        const byteLimit = [3,10000].includes(request.event?.kind) ? 1048576 : 131072;
        if (encoder.encode(event.data).length > byteLimit) { reply(null, 'Signing request is too large.'); return; }
        if (Date.now() - minute >= 60000) { minute = Date.now(); appCount = 0; relayCount = 0; }
        const count = relay ? ++relayCount : ++appCount;
        const waiting = [...pending.values()].filter(value => value === relay).length;
        if (count > (relay ? 240 : 120) || waiting >= (relay ? \#(relayPendingLimit) : \#(appPendingLimit))
            || pending.has(request.id)) { reply(null, 'Nostur request limit reached.'); return; }
        if (request.method !== 'getPublicKey' && request.method !== 'signEvent') { reply(null, 'Unsupported Nostur capability.'); return; }
        pending.set(request.id, relay);
        let timer;
        try {
          await Promise.race([ready, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('Page is not ready.')), 15000); })]);
          const message = JSON.stringify({documentToken: token, method: request.method, event: request.event});
          if (encoder.encode(message).length > byteLimit) throw new Error('Signing request is too large.');
          const result = await handler.postMessage(message);
          reply(JSON.parse(result), null);
        } catch (_) {
          // Do not reflect arbitrary native errors or web-controlled exceptions.
          reply(null, 'Nostur declined this request. Check Recent activity in Nostur.');
        } finally { clearTimeout(timer); pending.delete(request.id); }
      });
    })();
    """#
}
