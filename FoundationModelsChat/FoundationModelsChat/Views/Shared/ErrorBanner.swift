//
//  ErrorBanner.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//

import SwiftUI

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(.orange)
    }
}
