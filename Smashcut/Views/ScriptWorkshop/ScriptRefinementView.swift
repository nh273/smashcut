import SwiftUI

struct ScriptRefinementView: View {
    let refinedScript: String
    @Binding var sections: [String]
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Refined Script")
                .font(.headline)

            Text(refinedScript)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text("Sections (\(sections.count))")
                .font(.headline)

            ForEach(sections.indices, id: \.self) { idx in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(idx + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor)
                        .clipShape(Circle())

                    // TextField with vertical axis expands naturally inside ScrollView
                    // without the nested-scroll-view conflict that TextEditor causes.
                    TextField("Section \(idx + 1)", text: $sections[idx], axis: .vertical)
                        .lineLimit(2...10)
                        .padding(8)
                        .background(Color(.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.systemGray4))
                        )
                }
            }

            Button {
                onAccept()
            } label: {
                Label("Accept & Continue", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
    }
}
