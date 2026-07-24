//
//  MessageBubbleView.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//

import SwiftUI

struct MessageBubbleView: View {
    let message: AssistantViewModel.DisplayMessage
    let isStreaming: Bool

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }

            Group {
                if message.text.isEmpty && isStreaming {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 8)
                } else {
                    Text(message.text)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isUser ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(isUser ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))

            if !isUser { Spacer(minLength: 48) }
        }
    }
}
