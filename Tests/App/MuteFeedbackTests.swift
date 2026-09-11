import AppKit
import Testing
@testable import TelefonX

@Suite struct MuteFeedbackTests {
    @Test @MainActor func successfulMuteAndUnmutePlayDistinctSystemFeedback() async throws {
        let feedback = CapturingMuteFeedback()
        let model = PreviewFixtures.makeModel(muteFeedback: feedback)
        let initial = try #require(model.activeCalls.first)

        await model.mute(initial)
        let muted = try #require(model.activeCalls.first)
        #expect(muted.muted)
        await model.mute(muted)

        #expect(model.activeCalls.first?.muted == false)
        #expect(feedback.events.map(\.muted) == [true, false])
        #expect(feedback.events.allSatisfy { $0.outputUID == model.outputUID })
        #expect(MuteFeedbackPlayer.soundName(muted: true) == "Pop")
        #expect(MuteFeedbackPlayer.soundName(muted: false) == "Tink")
        #expect(NSSound(named: MuteFeedbackPlayer.soundName(muted: true)) != nil)
        #expect(NSSound(named: MuteFeedbackPlayer.soundName(muted: false)) != nil)
    }
}

@MainActor private final class CapturingMuteFeedback: MuteFeedbackPlaying {
    struct Event { let muted: Bool; let outputUID: String }
    var events: [Event] = []
    func play(muted: Bool, outputUID: String) { events.append(.init(muted: muted, outputUID: outputUID)) }
}
