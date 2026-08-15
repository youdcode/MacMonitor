import SwiftUI

/// The frame every detail screen sits in.
///
/// One place for the title, the spacing and the background, so the screens cannot
/// drift apart from each other. Spacing is tighter than it was: the content is almost
/// entirely numbers, and a monitor should be scannable in one glance rather than
/// scrolled through.
struct DetailScreen<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 2)

                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
