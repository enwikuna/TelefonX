import Foundation

/// Commercial packaging is deliberately a configuration decision, not SIP logic.
public enum PaidFeature: String, Codable, CaseIterable, Sendable {
    case additionalLines, contactImportExport, dialingRules, holdMusic, publicCallerLookup, callReminders, customRingtones
}

public struct FeatureAccess: Equatable, Sendable {
    public var internalEvaluation: Bool
    public var unlocked: Set<PaidFeature>
    public init(internalEvaluation: Bool = false, unlocked: Set<PaidFeature> = []) {
        self.internalEvaluation = internalEvaluation; self.unlocked = unlocked
    }
    public func permits(_ feature: PaidFeature) -> Bool { internalEvaluation || unlocked.contains(feature) }
    /// Revocation/expiration never interferes with incoming or already active calls.
    public var permitsBasicCalling: Bool { true }
    public var permitsControllingActiveCalls: Bool { true }
}
