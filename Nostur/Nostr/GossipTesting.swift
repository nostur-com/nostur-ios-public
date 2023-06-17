import SwiftUI

// 1. Input: following pubkeys
// 2. For every key, get relays from kind 3 or kind 10002
// 3. Build optimized set of relays that has all keys
// 4. Build secondary set, where each key is at least in another relay from the first set
// 5. Build third set, where the biggest relay is ignored

// 7. For keys without relay from 3 or 10002, query the bootstrap relay set

// 9. Track broken relays, if failed 1,2,4,8,16, 1 day. remove from set

struct GossipTesting: View {
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
    }
}

struct GossipTesting_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadContacts() }) {
            GossipTesting()
        }
    }
}



