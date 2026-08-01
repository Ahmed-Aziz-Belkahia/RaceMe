import SwiftUI

/// The wordmark, built out of the same parts as everything else: condensed black
/// numerals-grade type, a chalk lane line, and one rust accent. Drawn rather than
/// shipped as an asset so it inherits the palette and scales cleanly.
struct Wordmark: View {
    var size: CGFloat = 44
    /// Draws the lane rules above and below. Off inside dense chrome.
    var ruled: Bool = true

    var body: some View {
        VStack(spacing: size * 0.16) {
            if ruled { rule }
            HStack(spacing: 0) {
                Text("RACE")
                    .foregroundStyle(Track.chalk)
                Text("ME")
                    .foregroundStyle(Track.you)
            }
            .font(.system(size: size, weight: .black, design: .default).width(.compressed))
            .tracking(size * -0.02)
            if ruled { rule }
        }
        .accessibilityElement()
        .accessibilityLabel("RaceMe")
    }

    private var rule: some View {
        Rectangle()
            .fill(Track.chalk.opacity(0.22))
            .frame(height: 1)
    }
}

/// A safety-pinned bib. Used for the racer number on the card and the share
/// asset — four fat condensed numerals on off-white, with the pin holes.
struct BibNumber: View {
    let number: Int
    var width: CGFloat = 108

    private var height: CGFloat { width * 0.72 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Track.chalk)
            VStack(spacing: height * 0.04) {
                Text("RACEME")
                    .font(Bib.label(width * 0.075))
                    .labelTracking()
                    .foregroundStyle(Track.base.opacity(0.55))
                Text(String(format: "%04d", number % 10000))
                    .font(.system(size: width * 0.34, weight: .black, design: .default).width(.compressed).monospacedDigit())
                    .tracking(width * -0.008)
                    .foregroundStyle(Track.base)
            }
            // Pin holes, top corners. The detail that makes it a bib and not a card.
            VStack {
                HStack {
                    pinHole; Spacer(); pinHole
                }
                Spacer()
            }
            .padding(width * 0.055)
        }
        .frame(width: width, height: height)
        .accessibilityLabel("Bib number \(number % 10000)")
    }

    private var pinHole: some View {
        Circle()
            .fill(Track.base.opacity(0.25))
            .frame(width: width * 0.035, height: width * 0.035)
    }
}
