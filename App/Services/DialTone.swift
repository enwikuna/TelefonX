import Foundation

/// Short, softly ramped dual-tone feedback. No connection to RTP or microphone.
enum DialTone {
    static let sampleRate = 48_000
    static let duration = 0.12
    static let digits = Array("123456789*0#")
    static func frequencies(for digit: Character) -> (low: Double, high: Double)? {
        guard let index = digits.firstIndex(of: digit) else { return nil }
        return ([697.0, 770, 852, 941][index / 3], [1209.0, 1336, 1477][index % 3])
    }
    static func samples(for digit: Character) -> [Int16]? {
        guard let pair = frequencies(for: digit) else { return nil }
        let count = Int(Double(sampleRate) * duration), ramp = Double(sampleRate) * 0.005
        return (0..<count).map { frame in
            let time = Double(frame) / Double(sampleRate)
            let envelope = min(1, Double(frame) / ramp, Double(count - 1 - frame) / ramp)
            let value = (sin(2 * .pi * pair.low * time) + sin(2 * .pi * pair.high * time)) * 0.12 * envelope
            return Int16((value * Double(Int16.max)).rounded())
        }
    }
    static func waveData(for digit: Character) -> Data? {
        guard let samples = samples(for: digit) else { return nil }
        return waveData(samples: samples)
    }
    /// Three short local pulses indicate that an outgoing call was stopped
    /// before an INVITE because its SIP line could not be confirmed.
    static func callFailureWaveData() -> Data {
        let pulseFrames = Int(Double(sampleRate) * 0.14)
        let gapFrames = Int(Double(sampleRate) * 0.09)
        let ramp = Double(sampleRate) * 0.006
        var result: [Int16] = []
        for pulse in 0..<3 {
            result += (0..<pulseFrames).map { frame in
                let time = Double(frame) / Double(sampleRate)
                let envelope = min(1, Double(frame) / ramp, Double(pulseFrames - 1 - frame) / ramp)
                let value = sin(2 * .pi * 425 * time) * 0.14 * envelope
                return Int16((value * Double(Int16.max)).rounded())
            }
            if pulse < 2 { result += [Int16](repeating: 0, count: gapFrames) }
        }
        return waveData(samples: result)
    }
    private static func waveData(samples: [Int16]) -> Data {
        let byteCount = UInt32(samples.count * 2)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8); append(byteCount + 36)
        data.append(contentsOf: "WAVEfmt ".utf8); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1)); append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: "data".utf8); append(byteCount)
        for sample in samples { append(sample) }
        return data
    }
}
