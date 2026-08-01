import SwiftUI

/// Liquid Glass, used the way Apple asks it to be used.
///
/// Glass is the **floating interaction layer** — nav, primary actions, race
/// controls, header pills, sheets. Content lives underneath it and scrolls past.
///
/// It is not for body copy, lists, dense data, or anything with more than about
/// ten words in it. Glass never stacks on glass. If three glass surfaces are
/// visible at once, one of them is wrong and gets removed.
///
/// Everything here goes through `GlassEffectContainer` where surfaces are near
/// each other, so they merge and refract as one material instead of reading as
/// separate panes stuck to the screen.

// MARK: - Morph namespace

/// A single app-wide namespace for glass identity, so a nav action can *become*
/// the race-start button rather than cross-fading into it. That transformation
/// is the entire reason this capability exists.
struct GlassNamespaceKey: EnvironmentKey {
    @Namespace static var fallback
    static let defaultValue: Namespace.ID = fallback
}

extension EnvironmentValues {
    var glassNamespace: Namespace.ID {
        get { self[GlassNamespaceKey.self] }
        set { self[GlassNamespaceKey.self] = newValue }
    }
}

/// Stable identities for glass surfaces that morph across screens.
enum GlassID {
    static let primaryAction = "glass.primaryAction"   // Start → Race now → GO
    static let headerPill = "glass.headerPill"
    static let raceControls = "glass.raceControls"
    static let racerCard = "glass.racerCard"
    static let tabBar = "glass.tabBar"
}

// MARK: - Header pill

/// The recurring glass chip: distance · mode · elapsed. Short strings only —
/// this is a label, never a paragraph.
struct GlassPill<Content: View>: View {
    var tint: Color? = nil
    var morphID: String? = nil
    @ViewBuilder var content: Content

    @Environment(\.glassNamespace) private var ns

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .glassEffect(glass, in: .capsule)
            .modifier(OptionalGlassID(id: morphID, namespace: ns))
    }

    private var glass: Glass {
        if let tint { return .regular.tint(tint.opacity(0.28)) }
        return .regular
    }
}

private struct OptionalGlassID: ViewModifier {
    let id: String?
    let namespace: Namespace.ID
    func body(content: Content) -> some View {
        if let id {
            content.glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}

// MARK: - Primary action

/// The one loud thing on a screen. Rust-tinted glass, condensed caps label.
/// Carries a morph identity by default so it travels between screens instead of
/// fading out here and fading in there.
struct GlassAction: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Track.you
    var morphID: String? = GlassID.primaryAction
    var fullWidth: Bool = true
    var haptic: Haptic = .commit
    let action: () -> Void

    @Environment(\.glassNamespace) private var ns
    @Environment(\.motion) private var motion

    var body: some View {
        Button {
            Haptics.shared.play(haptic)
            action()
        } label: {
            HStack(spacing: 9) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .bold))
                }
                Text(title.uppercased())
                    .font(Bib.label(17))
                    .labelTracking()
            }
            .foregroundStyle(Track.chalk)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, fullWidth ? 0 : 26)
            .padding(.vertical, 19)
            .contentShape(.capsule)
        }
        .buttonStyle(.pressable(scale: 0.97, haptic: nil))
        .glassEffect(.regular.tint(tint.opacity(0.55)).interactive(), in: .capsule)
        .modifier(OptionalGlassID(id: morphID, namespace: ns))
    }
}

/// The quiet counterpart. Text-weight, always visible, never greyed out —
/// the free path stays honest.
struct QuietAction: View {
    let title: String
    var color: Color = Track.chalkDim
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.shared.play(.select)
            action()
        } label: {
            Text(title)
                .font(Body.copy(17))
                .foregroundStyle(color)
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .contentShape(.rect)
        }
        .buttonStyle(.pressable(scale: 0.98, haptic: nil))
    }
}

// MARK: - Floating control bar

/// Race controls. One container so the buttons inside merge and refract as a
/// single piece of material rather than three separate panes.
struct GlassControlBar<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            HStack(spacing: spacing) { content }
        }
    }
}

/// A single circular control inside a `GlassControlBar`.
struct GlassCircleButton: View {
    let systemImage: String
    var tint: Color? = nil
    var size: CGFloat = 58
    var haptic: Haptic = .select
    var accessibilityName: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.shared.play(haptic)
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(tint ?? Track.chalk)
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.pressable(scale: 0.9, haptic: nil))
        .glassEffect(
            tint.map { Glass.regular.tint($0.opacity(0.4)).interactive() } ?? .regular.interactive(),
            in: .circle
        )
        .accessibilityLabel(accessibilityName)
    }
}

// MARK: - Sheet surface

/// Sheets are glass. Their *contents* are not — dense data sits on the plain
/// elevated surface inside, because glass under a list is unreadable and cheap.
struct GlassSheet<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(22)
            .glassEffect(.regular.tint(Track.elevated.opacity(0.5)), in: .rect(cornerRadius: 30))
    }
}

// MARK: - Non-glass surfaces
//
// Most of the app is this, not glass. Lists, cards, stat blocks, leaderboard
// rows. Solid, cheap to render, legible at arm's length in daylight.

struct TrackSurface<Content: View>: View {
    var corner: CGFloat = 22
    var stroke: Color = Track.hairline
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Track.elevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(stroke, lineWidth: 1)
                    }
            }
    }
}
