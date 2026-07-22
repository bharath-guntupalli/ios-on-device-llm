//
//  ChatTemplate.swift
//  OnDeviceLLM
//
//  Created by Guntupalli, Bharath on 21/07/26.
//
//  Renders conversation turns into the exact prompt markup each model family
//  was trained on. These strings are format-sensitive: a missing newline or a
//  stray space degrades output quality, so the templates are kept as literal
//  as possible.
//
//  Cache invariant: after the first turn, only `renderSuffix` output is ever
//  tokenized and appended behind the existing KV cache. Past turns are never
//  re-rendered while the cache is valid, because retokenizing sampled text is
//  not guaranteed to reproduce the token ids that were actually decoded.
//

import Foundation
import LLMEngineKit

nonisolated struct ChatTemplate: Sendable {
    let family: ChatTemplateFamily
    var systemPrompt: String

    init(family: ChatTemplateFamily,
         systemPrompt: String = "You are a helpful assistant.") {
        self.family = family
        self.systemPrompt = systemPrompt
    }

    // MARK: - Rendering

    /// Full prompt: system message, every turn in `history`, and an open
    /// assistant header for the model to complete. Used on the first turn and
    /// whenever the KV cache is rebuilt after trimming.
    func renderFull(history: [ChatMessage]) -> String {
        switch family {
        case .llama3:
            var text = "<|begin_of_text|>"
            text += llama3Turn(role: "system", content: systemPrompt)
            for message in history {
                text += llama3Turn(role: message.role.rawValue, content: message.content)
            }
            text += "<|start_header_id|>assistant<|end_header_id|>\n\n"
            return text

        case .chatML:
            var text = chatMLTurn(role: "system", content: systemPrompt)
            for message in history {
                text += chatMLTurn(role: message.role.rawValue, content: message.content)
            }
            text += "<|im_start|>assistant\n"
            return text
        }
    }

    /// Incremental prompt appended verbatim behind the tokens already in the
    /// KV cache. The previous assistant turn is still "open" in the cache
    /// (generation stopped at an end-of-generation token that was never
    /// decoded), so this starts by closing it.
    func renderSuffix(newUserMessage: String) -> String {
        switch family {
        case .llama3:
            return "<|eot_id|>"
                + llama3Turn(role: "user", content: newUserMessage)
                + "<|start_header_id|>assistant<|end_header_id|>\n\n"

        case .chatML:
            return "<|im_end|>\n"
                + chatMLTurn(role: "user", content: newUserMessage)
                + "<|im_start|>assistant\n"
        }
    }

    // MARK: - Per-family turn markup

    private func llama3Turn(role: String, content: String) -> String {
        "<|start_header_id|>\(role)<|end_header_id|>\n\n\(content)<|eot_id|>"
    }

    private func chatMLTurn(role: String, content: String) -> String {
        "<|im_start|>\(role)\n\(content)<|im_end|>\n"
    }
}
