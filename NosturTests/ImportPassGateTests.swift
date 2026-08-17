import Testing
@testable import Nostur

@Suite("Importer pass scheduling")
struct ImportPassGateTests {
    @Test("Only one Core Data pass can be queued at a time")
    func coalescesTriggersBeforeQueuedWorkStarts() {
        let gate = ImportPassGate()

        #expect(gate.begin())
        #expect(gate.isScheduled)
        #expect(!gate.begin())
        #expect(!gate.begin())

        gate.finish()

        #expect(!gate.isScheduled)
        #expect(gate.begin())
    }
}
