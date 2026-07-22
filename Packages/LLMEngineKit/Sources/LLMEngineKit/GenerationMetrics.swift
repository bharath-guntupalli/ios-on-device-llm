//
//  GenerationMetrics.swift
//  LLMEngineKit
//
//  Created by Guntupalli, Bharath on 22/07/26.
//
//  Per-generation measurements powering the showcase's benchmark comparison
//  (Phase 4): time-to-first-token, throughput, and peak memory.
//

import Foundation

public struct GenerationMetrics: Sendable, Equatable {
    /// Seconds from the generate() call until the first delta was yielded.
    public var timeToFirstToken: TimeInterval?
    /// Seconds spent generating (first delta → completion).
    public var generationDuration: TimeInterval?
    /// Number of tokens produced (engine-reported where available).
    public var tokensGenerated: Int
    /// Highest observed process memory footprint during generation, in bytes.
    public var peakMemoryBytes: Int?

    /// Decode throughput; nil until duration and token count are both known.
    public var tokensPerSecond: Double? {
        guard let generationDuration, generationDuration > 0, tokensGenerated > 0 else {
            return nil
        }
        return Double(tokensGenerated) / generationDuration
    }

    public init(timeToFirstToken: TimeInterval? = nil,
                generationDuration: TimeInterval? = nil,
                tokensGenerated: Int = 0,
                peakMemoryBytes: Int? = nil) {
        self.timeToFirstToken = timeToFirstToken
        self.generationDuration = generationDuration
        self.tokensGenerated = tokensGenerated
        self.peakMemoryBytes = peakMemoryBytes
    }
}
