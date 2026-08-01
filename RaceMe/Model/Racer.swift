import SwiftUI

/// Six tap-to-cycle geometric marks. Not a photo upload.
///
/// Zero friction and real ownership: the shape is theirs, the colour is theirs,
/// and nobody has to go find a picture of themselves at 6am to finish signing up.
enum AvatarMark: Int, CaseIterable, Codable, Sendable, Identifiable {
    case chevron, bars, ring, blade, grid, spike
    var id: Int { rawValue }
}

struct Racer: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var handle: String
    /// The name a human would shout. Rivals from onboarding use their first name here.
    var displayName: String
    var mark: AvatarMark
    var isUser: Bool

    /// Recent-form pace in seconds per kilometre. This is the number the whole
    /// handicap system runs on, and it's the number that lets a 12:00/mi runner
    /// beat a 7:00/mi runner by outperforming themselves.
    var handicapPaceSecPerKm: Double

    /// Personal best over 5K in seconds, if they have one on record.
    var pb5K: Double?
    var careerWins: Int
    var careerLosses: Int
    /// Assigned once at creation, and only for opponents. `isUser` racers are
    /// always drawn in `Track.you`, no exceptions.
    var colorIndex: Int

    init(
        id: UUID = UUID(),
        handle: String,
        displayName: String? = nil,
        mark: AvatarMark = .chevron,
        isUser: Bool = false,
        handicapPaceSecPerKm: Double,
        pb5K: Double? = nil,
        careerWins: Int = 0,
        careerLosses: Int = 0,
        colorIndex: Int = 0
    ) {
        self.id = id
        self.handle = handle
        self.displayName = displayName ?? handle
        self.mark = mark
        self.isUser = isUser
        self.handicapPaceSecPerKm = handicapPaceSecPerKm
        self.pb5K = pb5K
        self.careerWins = careerWins
        self.careerLosses = careerLosses
        self.colorIndex = colorIndex
    }

    var color: Color { Track.racer(isUser: isUser, opponentIndex: colorIndex) }

    var record: String { "\(careerWins)\u{2013}\(careerLosses)" }

    var winRate: Double {
        let total = careerWins + careerLosses
        return total == 0 ? 0 : Double(careerWins) / Double(total)
    }

    /// Expected finishing time at handicap pace.
    func expectedTime(over meters: Double) -> Double {
        handicapPaceSecPerKm * meters / 1000
    }
}

/// The geometric avatar. Drawn, not shipped as an asset, so it inherits the
/// racer's colour automatically and can't drift out of palette.
struct AvatarView: View {
    let mark: AvatarMark
    let color: Color
    var size: CGFloat = 44
    /// Rings the mark. Used to show who's leading in a group.
    var emphasized: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.16))
            if emphasized {
                Circle().strokeBorder(color, lineWidth: 2)
            } else {
                Circle().strokeBorder(color.opacity(0.4), lineWidth: 1)
            }
            shape
                .stroke(color, style: .init(lineWidth: size * 0.075, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.46, height: size * 0.46)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// `AnyShape`, not `@ViewBuilder`. ViewBuilder composes branches into
    /// `_ConditionalContent`, which conforms to `View` but not to `Shape` — so a
    /// switch returning `some Shape` can't be built that way.
    private var shape: AnyShape {
        switch mark {
        case .chevron: AnyShape(ChevronMark())
        case .bars: AnyShape(BarsMark())
        case .ring: AnyShape(RingMark())
        case .blade: AnyShape(BladeMark())
        case .grid: AnyShape(GridMark())
        case .spike: AnyShape(SpikeMark())
        }
    }
}

// Six marks, all drawn from the same vocabulary as the lane and the finish
// line: chevrons, hurdles, rings, blades, chip mats, spikes. Nothing rounded
// and friendly, nothing that could be a wellness app's mascot.

private struct ChevronMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: r.minX, y: r.maxY))
        p.addLine(to: .init(x: r.midX, y: r.minY))
        p.addLine(to: .init(x: r.maxX, y: r.maxY))
        return p
    }
}

private struct BarsMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0..<3 {
            let y = r.minY + r.height * (0.15 + 0.35 * Double(i))
            p.move(to: .init(x: r.minX + r.width * Double(i) * 0.16, y: y))
            p.addLine(to: .init(x: r.maxX, y: y))
        }
        return p
    }
}

private struct RingMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: r.insetBy(dx: r.width * 0.08, dy: r.height * 0.22))
        return p
    }
}

private struct BladeMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: .init(x: r.maxX, y: r.minY), control: .init(x: r.maxX * 0.9, y: r.maxY * 0.9))
        p.addLine(to: .init(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

private struct GridMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0...2 {
            let t = Double(i) / 2
            p.move(to: .init(x: r.minX + r.width * t, y: r.minY))
            p.addLine(to: .init(x: r.minX + r.width * t, y: r.maxY))
            p.move(to: .init(x: r.minX, y: r.minY + r.height * t))
            p.addLine(to: .init(x: r.maxX, y: r.minY + r.height * t))
        }
        return p
    }
}

private struct SpikeMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: r.midX, y: r.minY))
        p.addLine(to: .init(x: r.maxX, y: r.midY))
        p.addLine(to: .init(x: r.midX, y: r.maxY))
        p.addLine(to: .init(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}
