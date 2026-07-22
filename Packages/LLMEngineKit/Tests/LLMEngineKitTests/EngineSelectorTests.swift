//
//  EngineSelectorTests.swift
//  LLMEngineKit
//
//  Created by Guntupalli, Bharath on 22/07/26.
//

import Testing
@testable import LLMEngineKit

/// Trivial engine stand-in for selector tests.
private struct StubEngine: LLMEngine {
    static var engineName: String { "stub" }
    static func availability() -> EngineAvailability { .available }
    let tag: String
    func load() async throws {}
    func unload() async {}
    func generate(_ userMessage: String) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func stopGenerating() async {}
    func resetConversation() async {}
}

private func candidate(_ name: String, available: Bool) -> EngineCandidate {
    EngineCandidate(
        name: name,
        availability: { available ? .available : .unavailable(reason: "\(name) unsupported") },
        make: { StubEngine(tag: name) }
    )
}

@Suite struct EngineSelectorTests {

    @Test func firstAvailableRespectsChainOrder() {
        let engine = EngineSelector.firstAvailable(from: [
            candidate("foundation-models", available: false),
            candidate("mlx", available: true),
            candidate("llama.cpp", available: true),
        ])
        #expect((engine as? StubEngine)?.tag == "mlx")
    }

    @Test func firstAvailableReturnsNilWhenNothingRuns() {
        let engine = EngineSelector.firstAvailable(from: [
            candidate("foundation-models", available: false),
            candidate("mlx", available: false),
        ])
        #expect(engine == nil)
    }

    @Test func probeAllReportsEveryCandidateInOrder() {
        let probes = EngineSelector.probeAll([
            candidate("foundation-models", available: false),
            candidate("llama.cpp", available: true),
        ])
        #expect(probes.map(\.name) == ["foundation-models", "llama.cpp"])
        #expect(probes[0].availability == .unavailable(reason: "foundation-models unsupported"))
        #expect(probes[1].availability == .available)
    }

    @Test func defaultMetricsAreNil() async {
        let engine: any LLMEngine = StubEngine(tag: "stub")
        let metrics = await engine.lastMetrics
        #expect(metrics == nil)
    }
}
