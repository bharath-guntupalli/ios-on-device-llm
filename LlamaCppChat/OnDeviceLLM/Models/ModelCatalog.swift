//
//  ModelCatalog.swift
//  OnDeviceLLM
//
//  Created by Guntupalli, Bharath on 21/07/26.
//
//  The catalog of GGUF models the app knows how to download and run.
//  Adding a new model is a single entry in `ModelCatalog.all`.
//

import Foundation

/// Prompt-format family a model expects. Determines how conversation turns
/// are rendered into the raw token stream (see `ChatTemplate`).
nonisolated enum ChatTemplateFamily: String, Sendable, Codable {
    /// LLaMA 3.x instruct markup: `<|start_header_id|>role<|end_header_id|> … <|eot_id|>`
    case llama3
    /// ChatML (Qwen, and many others): `<|im_start|>role\n … <|im_end|>`
    case chatML
}

/// A downloadable, runnable model definition.
nonisolated struct ModelSpec: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let fileName: String
    let downloadURL: URL
    /// Used for the disk-space preflight and as a fallback when the server
    /// doesn't report Content-Length.
    let approxSizeBytes: Int64
    let family: ChatTemplateFamily
    /// Conservative context window sized for 4GB devices (iPhone 12).
    let recommendedContext: Int32

    /// Final on-disk location: Documents/Models/<fileName>.
    var localURL: URL {
        ModelCatalog.modelsDirectory.appendingPathComponent(fileName)
    }

    /// True only if the file exists, is plausibly sized, and starts with the
    /// GGUF magic bytes — a truncated or HTML-error-page download never
    /// passes, so a corrupt file can't route the user into a crashing chat.
    var isDownloaded: Bool {
        let url = localURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              size > 100 * 1024 * 1024 else {
            return false
        }
        return Self.hasGGUFMagic(at: url)
    }

    /// GGUF files begin with the ASCII bytes "GGUF".
    static func hasGGUFMagic(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let magic = try? handle.read(upToCount: 4)
        return magic == Data([0x47, 0x47, 0x55, 0x46]) // "GGUF"
    }
}

nonisolated enum ModelCatalog {
    /// All models offered in the setup UI. Order is display order.
    static let all: [ModelSpec] = [
        ModelSpec(
            id: "llama-3.2-1b-instruct-q4km",
            displayName: "Llama 3.2 1B Instruct (Q4_K_M)",
            fileName: "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf")!,
            approxSizeBytes: 808_000_000,
            family: .llama3,
            recommendedContext: 2048
        ),
        ModelSpec(
            id: "qwen2.5-1.5b-instruct-q4km",
            displayName: "Qwen 2.5 1.5B Instruct (Q4_K_M)",
            fileName: "Qwen2.5-1.5B-Instruct-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf")!,
            approxSizeBytes: 990_000_000,
            family: .chatML,
            recommendedContext: 2048
        ),
    ]

    static func spec(withID id: String) -> ModelSpec? {
        all.first { $0.id == id }
    }

    /// Documents/Models — created on first access. Lives in Documents so the
    /// user can inspect/remove weights via the Files app; backup exclusion is
    /// applied per-file after download.
    static var modelsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Models", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
