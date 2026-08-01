import Foundation

/// Deterministic RNG. Not a convenience — a requirement.
///
/// A challenge link has to reproduce the *same* ghost on your friend's phone
/// that it produced on yours, and a photo finish has to be reproducible from a
/// stored result. Both fall apart with `SystemRandomNumberGenerator`.
struct Rng: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Avoid the zero fixed point of SplitMix64.
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    init(seed: String) {
        var h: UInt64 = 0xCBF29CE484222325
        for byte in seed.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x100000001B3
        }
        self.init(seed: h)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    mutating func range(_ lo: Double, _ hi: Double) -> Double {
        lo + unit() * (hi - lo)
    }

    /// Standard normal, Box–Muller. Pace noise is Gaussian in the real world;
    /// uniform noise reads as machine jitter rather than a body.
    mutating func gaussian() -> Double {
        let u1 = max(unit(), 1e-12)
        let u2 = unit()
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[Int(next() % UInt64(items.count))]
    }

    mutating func chance(_ p: Double) -> Bool { unit() < p }
}
