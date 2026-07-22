//
//  EngineSelector.swift
//  LLMEngineKit
//
//  Created by Guntupalli, Bharath on 22/07/26.
//
//  The production fallback story: walk an ordered list of engine candidates
//  and use the first one whose availability probe passes. A typical chain is
//
//      Apple Foundation Models  (zero download, iOS 26+, AI-eligible only)
//        → MLX                  (Metal-optimized, device only)
//          → llama.cpp          (runs anywhere)
//            → cloud            (production last resort)
//
//  `EngineCandidate` is a factory struct rather than `any LLMEngine.Type`
//  because engines take heterogeneous configuration at init — a metatype
//  cannot carry a model URL or Hub model ID.
//

public struct EngineCandidate: Sendable {
    public let name: String
    public let availability: @Sendable () -> EngineAvailability
    public let make: @Sendable () -> any LLMEngine

    public init(name: String,
                availability: @escaping @Sendable () -> EngineAvailability,
                make: @escaping @Sendable () -> any LLMEngine) {
        self.name = name
        self.availability = availability
        self.make = make
    }
}

public enum EngineSelector {

    /// Walks candidates in order; the first `.available` one is instantiated.
    /// Returns nil when nothing on the device can run (callers decide whether
    /// that means a cloud fallback or an error screen).
    public static func firstAvailable(from candidates: [EngineCandidate]) -> (any LLMEngine)? {
        for candidate in candidates where candidate.availability().isAvailable {
            return candidate.make()
        }
        return nil
    }

    /// Diagnostic variant for settings/debug UI: every candidate with its
    /// probe result, in chain order.
    public static func probeAll(
        _ candidates: [EngineCandidate]
    ) -> [(name: String, availability: EngineAvailability)] {
        candidates.map { ($0.name, $0.availability()) }
    }
}
