import Foundation

extension Duration {
    /// Whole nanoseconds, for arithmetic on delays.
    ///
    /// `Duration` exposes its value as a (seconds, attoseconds) pair, which is awkward
    /// to compute with when all you want is to scale a delay.
    var nanoseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
    }
}
