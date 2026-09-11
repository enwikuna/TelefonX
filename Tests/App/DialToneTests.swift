import Foundation
import Testing
@testable import TelefonX

@Suite struct DialToneTests {
    @Test(arguments: Array("123456789*0#"))
    func digitHasCorrectDualToneAndSoftEdges(_ digit: Character) throws {
        let expectedRows = [697.0, 770, 852, 941], expectedColumns = [1209.0, 1336, 1477]
        let index = try #require(Array("123456789*0#").firstIndex(of: digit))
        let samples = try #require(DialTone.samples(for: digit))
        #expect(samples.count == 5_760)
        #expect(samples.first == 0 && samples.last == 0)
        #expect(samples.allSatisfy { abs(Int($0)) < 8_000 })
        let powers = (expectedRows + expectedColumns).map { frequency in
            let real = samples.enumerated().reduce(0.0) { result, sample in
                result + Double(sample.element) * cos(2 * .pi * frequency * Double(sample.offset) / 48_000)
            }
            let imaginary = samples.enumerated().reduce(0.0) { result, sample in
                result + Double(sample.element) * sin(2 * .pi * frequency * Double(sample.offset) / 48_000)
            }
            return real * real + imaginary * imaginary
        }
        let expectedIndices = [index / 3, 4 + index % 3]
        for expected in expectedIndices {
            #expect(powers[expected] > 1_000_000)
            for other in powers.indices where !expectedIndices.contains(other) {
                #expect(powers[expected] > 100 * powers[other])
            }
        }
    }

    @Test func validPCMContainerAndUnsupportedCharacters() throws {
        let wave = try #require(DialTone.waveData(for: "5"))
        #expect(wave.count == 44 + 5_760 * 2)
        #expect(String(data: wave[0..<4], encoding: .utf8) == "RIFF")
        #expect(String(data: wave[8..<16], encoding: .utf8) == "WAVEfmt ")
        #expect(String(data: wave[36..<40], encoding: .utf8) == "data")
        #expect(Array(wave[22..<24]) == [1, 0]) // Mono.
        #expect(Array(wave[24..<28]) == [128, 187, 0, 0]) // 48 kHz, little-endian.
        #expect(Array(wave[34..<36]) == [16, 0]) // PCM16.
        for character: Character in ["a", "+", " ", "\n"] {
            #expect(DialTone.waveData(for: character) == nil)
        }
    }

    @Test func callFailureSignalContainsThreePulsesAndTwoSilentGaps() {
        let wave = DialTone.callFailureWaveData()
        let pulseFrames = 6_720, gapFrames = 4_320
        #expect(wave.count == 44 + (pulseFrames * 3 + gapFrames * 2) * 2)
        #expect(String(data: wave[0..<4], encoding: .utf8) == "RIFF")
        let firstGapOffset = 44 + pulseFrames * 2
        #expect(wave[firstGapOffset..<(firstGapOffset + gapFrames * 2)].allSatisfy { $0 == 0 })
        let secondGapOffset = 44 + (pulseFrames * 2 + gapFrames) * 2
        #expect(wave[secondGapOffset..<(secondGapOffset + gapFrames * 2)].allSatisfy { $0 == 0 })
    }
}
