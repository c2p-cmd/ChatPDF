import SwiftUI

struct LoadingView: View {
    var fileName: String?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Reading document…")
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if let fileName {
            "Indexing “\(fileName)” on this Mac"
        } else {
            "Indexing on this Mac"
        }
    }
}

#Preview {
    LoadingView(fileName: "paper.pdf")
}
