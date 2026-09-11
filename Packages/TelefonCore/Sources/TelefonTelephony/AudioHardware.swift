import CoreAudio
import Foundation

public enum AudioHardware {
    public struct Device: Sendable {
        public let id: AudioDeviceID
        public let uid: String
        public let name: String
        public let hasInput: Bool
        public let hasOutput: Bool
    }
    public static func devices() -> [Device] {
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
            return Device(id: id, uid: uid, name: name,
                          hasInput: hasStreams(id, scope: kAudioDevicePropertyScopeInput),
                          hasOutput: hasStreams(id, scope: kAudioDevicePropertyScopeOutput))
        }
    }
    public static func defaultInputUID() -> String? {
        defaultDeviceUID(kAudioHardwarePropertyDefaultInputDevice)
    }
    public static func defaultOutputUID() -> String? {
        defaultDeviceUID(kAudioHardwarePropertyDefaultOutputDevice)
    }
    private static func defaultDeviceUID(_ selector: AudioObjectPropertySelector) -> String? {
        var property = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return string(id, kAudioDevicePropertyDeviceUID)
    }
    private static func hasStreams(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
            mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &property, 0, nil, &size) == noErr && size > 0
    }
    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var property = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                   mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
