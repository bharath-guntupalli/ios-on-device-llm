//
//  EngineAvailability.swift
//  LLMEngineKit
//
//  Created by Guntupalli, Bharath on 22/07/26.
//
//  Result of a device/OS support probe. The reason string exists because
//  engines fail for user-actionable reasons — e.g. Apple Foundation Models
//  distinguishes "device not eligible" from "Apple Intelligence not enabled"
//  from "model still downloading" — and a fallback UI should say which.
//

public enum EngineAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}
