import SwiftUI

/// What a notice is saying: an outcome, a warning, or a failure.
///
/// Before this, setup-needed, notifications-off, the rate limit and asks all
/// shared one red, and a failed push was drawn in the same dim grey as a
/// successful one. Kind now carries the difference in an icon as well as a
/// hue, so a failure still reads as one without color.
enum NoticeKind {
    case info, warning, error

    var tint: Color {
        switch self {
        case .info: return .secondary
        case .warning: return .usageAmber
        case .error: return .usageRed
        }
    }

    var symbol: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
}

/// A message and what kind it is, for views that hold one in state. Kept free
/// of SwiftUI types so non-UI code (`GitActions`) can hand one back.
struct NoticeMessage: Equatable {
    let kind: NoticeKind
    let text: String
}

/// The one style for a message that isn't a session state.
struct Notice<Accessory: View>: View {
    let kind: NoticeKind
    let text: String
    var size: CGFloat = 10
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: kind.symbol).foregroundStyle(kind.tint)
            Text(text)
                .foregroundStyle(kind == .info ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            accessory
        }
        .font(.claudeMono(size))
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(kind.tint.opacity(kind == .info ? 0.06 : 0.12),
                    in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
    }
}

extension Notice where Accessory == EmptyView {
    init(kind: NoticeKind, text: String, size: CGFloat = 10) {
        self.init(kind: kind, text: text, size: size) { EmptyView() }
    }

    init(_ message: NoticeMessage, size: CGFloat = 10) {
        self.init(kind: message.kind, text: message.text, size: size)
    }
}


/// A text link in the `attention` blue. The system link style draws the system
/// blue, which measured 4.16:1 on the light sidebar for 10pt text; this one is
/// about 5:1 there and 7:1 on the dark one.
struct AttentionLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.attention)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .pointerStyle(.link)
    }
}

extension ButtonStyle where Self == AttentionLinkStyle {
    static var attentionLink: AttentionLinkStyle { AttentionLinkStyle() }
}
