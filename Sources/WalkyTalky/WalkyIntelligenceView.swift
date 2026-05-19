import SwiftUI

struct WalkyIntelligenceView: View {
    let result: WalkyIntelligenceResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(result.title.lowercased())
                    .font(.walky(.title2, weight: .semibold)).tracking(0.22)

                if !result.summary.isEmpty {
                    section("summary", items: result.summary)
                }

                if !result.actionItems.isEmpty {
                    section("action items", items: result.actionItems)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("cleaned transcript")
                        .font(.walky(.headline)).tracking(0.17)
                    Text(result.cleanedText.isEmpty ? "no transcript text available." : result.cleanedText.lowercased())
                        .font(.walky(.body)).tracking(0.14)
                        .textSelection(.enabled)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 720, height: 640)
        .walkyDefaultTypography()
    }

    private func section(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.lowercased())
                .font(.walky(.headline)).tracking(0.17)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                    Text(item.lowercased())
                        .textSelection(.enabled)
                }
                .font(.walky(.body)).tracking(0.14)
            }
        }
    }
}
