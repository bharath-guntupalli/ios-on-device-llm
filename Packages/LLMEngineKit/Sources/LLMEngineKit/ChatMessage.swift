//
//  ChatMessage.swift
//  LLMEngineKit
//
//  Created by Guntupalli, Bharath on 22/07/26.
//
//  One conversation turn, shared by every engine and every app's UI layer.
//

import Foundation

public struct ChatMessage: Sendable, Identifiable, Hashable, Codable {
    public enum Role: String, Sendable, Codable {
        case system, user, assistant
    }

    public let id: UUID
    public let role: Role
    public var content: String

    public init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}
