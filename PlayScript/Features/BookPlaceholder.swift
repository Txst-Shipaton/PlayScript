import SwiftUI

struct LibraryBook: Identifiable {
    let title: String
    let author: String
    let symbol: String
    let color: UInt32
    var id: String { title }
    static let upcoming: [LibraryBook] = [
        .init(title: "Sherlock Holmes", author: "Arthur Conan Doyle", symbol: "magnifyingglass", color: 0x314A49),
        .init(title: "Dracula", author: "Bram Stoker", symbol: "moonphase.waning.crescent", color: 0x512936),
        .init(title: "Vampire Diaries", author: "L. J. Smith", symbol: "drop", color: 0x452F49),
        .init(title: "Lord of the Rings", author: "J. R. R. Tolkien", symbol: "leaf", color: 0x5C5439),
        .init(title: "Harry Potter", author: "J. K. Rowling", symbol: "sparkles", color: 0x343A57),
    ]
}

struct BookPlaceholder: View {
    let book: LibraryBook
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 16) {
                SmallLabel(text: "PlayScript").font(.caption2)
                Spacer(minLength: 2)
                Image(systemName: book.symbol)
                    .font(.system(size: 35, weight: .ultraLight)).accessibilityHidden(true)
                Text(book.title).literary(23, relativeTo: .title3).multilineTextAlignment(.center)
                Spacer(minLength: 2)
                Text(book.author).font(.caption2).multilineTextAlignment(.center)
            }
            .foregroundStyle(Color(hex: 0xF6E0BA))
            .padding(20)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 240)
            .background(LinearGradient(colors: [Color(hex: book.color), Color(hex: book.color).opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .leading) {
                LinearGradient(colors: [.black.opacity(0.3), .white.opacity(0.1), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 12)
            }
            .overlay(Rectangle().stroke(Color(hex: 0xF6E0BA).opacity(0.3), lineWidth: 0.5).padding(10))
            .clipShape(.rect(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 13, topTrailingRadius: 13))
            .shadow(color: .black.opacity(0.12), radius: 8, x: 4, y: 5)
            Label("Coming soon", systemImage: "lock")
                .font(.caption).foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.title), by \(book.author). Coming soon. Not playable yet.")
        .accessibilityIdentifier("placeholder-\(book.title)")
    }
}
