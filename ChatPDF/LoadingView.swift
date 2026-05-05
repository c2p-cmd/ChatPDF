import SwiftUI

struct LoadingView: View {
    let title: String

    init(title: String = "Processing document...") {
        self.title = title
    }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
            Text(title)
                .foregroundStyle(Color.primary)
                .font(.headline)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
//        .background(Color.appBackground)
    }
}

#Preview {
    LoadingView()
}
