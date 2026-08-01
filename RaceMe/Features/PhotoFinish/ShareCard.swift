import SwiftUI

/// The 9:16 share card, built around the finish strip.
///
/// No glass — this gets flattened to a PNG and posted somewhere with an unknown
/// background, and a translucent material with nothing behind it renders as grey
/// mud. Solid surfaces, big numerals, the photo finish doing the talking.
struct ShareCardView: View {
    let result: RaceResult
    let film: PhotoFinishFilm
    let profile: RunnerProfile

    /// 1080 × 1920 at render time; laid out at 1/3 and scaled by ImageRenderer.
    static let size = CGSize(width: 360, height: 640)

    var body: some View {
        ZStack {
            Track.base

            // Same ambient field as the app, frozen — the card should look like
            // it was cut out of the product, not designed separately.
            RadialGradient(
                colors: [result.userWon ? Track.you.opacity(0.16) : Track.them.opacity(0.11), .clear],
                center: .init(x: 0.5, y: 0.28), startRadius: 0, endRadius: 420
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        TrackLabel(Fmt.raceName(result.config.distanceMeters), color: Track.chalkFaint, size: 13)
                        Text(headline)
                            .font(Bib.numeral(64))
                            .bibTracking(64)
                            .foregroundStyle(result.userWon ? Track.you : Track.chalk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer()
                    BibNumber(number: profile.totalRaces, width: 76)
                }
                .padding(.horizontal, 26)
                .padding(.top, 40)

                Text(subhead)
                    .font(Body.copy(17))
                    .foregroundStyle(Track.chalkDim)
                    .padding(.horizontal, 26)
                    .padding(.top, 10)

                Spacer(minLength: 20)

                // The strip is the picture. It gets the middle of the card and
                // the most vertical space of anything on it.
                VStack(alignment: .leading, spacing: 8) {
                    TrackLabel("Photo finish", size: 11)
                        .padding(.horizontal, 26)
                    PhotoFinishView(film: film, develop: 1, showsChrome: true, columns: 700)
                        .frame(height: 168)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(.horizontal, 20)
                }

                Spacer(minLength: 20)

                HStack(spacing: 0) {
                    stat("TIME", Fmt.clock(result.userTime))
                    stat("PACE", Fmt.pace(result.userPace, unit: profile.unit) + "/\(profile.unit.short.lowercased())")
                    stat("MARGIN", marginText)
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 24)

                HStack {
                    Wordmark(size: 20, ruled: false)
                    Spacer()
                    Text("raceme.app")
                        .font(Bib.label(11))
                        .labelTracking()
                        .foregroundStyle(Track.chalkFaint)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 30)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            TrackLabel(label, size: 10)
            Text(value)
                .font(Bib.numeral(26))
                .bibTracking(26)
                .foregroundStyle(Track.chalk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var headline: String {
        if result.isPersonalRecord { return "PR" }
        return result.userWon ? "WON" : "LOST"
    }

    private var subhead: String {
        guard let opponent = result.config.participants.first(where: { !$0.isUser }) else {
            return Fmt.clock(result.userTime)
        }
        let margin = abs(result.margin)
        if margin < 1 {
            return result.userWon
                ? "Beat \(opponent.displayName) by less than a second."
                : "\(opponent.displayName) got it by less than a second."
        }
        return result.userWon
            ? "Beat \(opponent.displayName) by \(Fmt.clock(margin))."
            : "\(opponent.displayName) by \(Fmt.clock(margin))."
    }

    private var marginText: String {
        let m = abs(result.margin)
        return m < 60 ? String(format: "%.2fs", m) : Fmt.clock(m)
    }
}

// MARK: - Rendering

@MainActor
enum ShareCardRenderer {
    /// Flatten to a PNG at 3× so it looks right pasted into a story.
    static func render(result: RaceResult, profile: RunnerProfile) -> UIImage? {
        let film = PhotoFinishFilm.build(from: result)
        let renderer = ImageRenderer(content: ShareCardView(result: result, film: film, profile: profile))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
