import Foundation
import Testing

@testable import Propr

/// The working streak travels along the bar's edge at an even pace. These pin down
/// where its head points for a given share of the way round.
struct WorkingEdgeTests {
    private func degrees(_ progress: CGFloat?, _ size: CGSize) -> Double {
        WorkingEdge.headAngle(progress: progress, in: size).degrees
    }

    @Test("The head walks clockwise from the top-left corner")
    func clockwise() {
        let square = CGSize(width: 100, height: 100)
        #expect(abs(degrees(0.125, square) - -90) < 0.001)  // middle of the top edge
        #expect(abs(degrees(0.375, square) - 0) < 0.001)  // middle of the right edge
        #expect(abs(degrees(0.625, square) - 90) < 0.001)  // middle of the bottom edge
        #expect(abs(abs(degrees(0.875, square)) - 180) < 0.001)  // middle of the left edge
    }

    @Test("It is placed by distance along the edge, not by angle")
    func byDistance() {
        // A wide bar: the first 500 of its 1,200 points of edge are the top.
        let bar = CGSize(width: 500, height: 100)
        #expect(abs(degrees(250.0 / 1_200, bar) - -90) < 0.001)
    }

    @Test("With Reduce Motion it holds at the top")
    func still() {
        #expect(degrees(nil, CGSize(width: 500, height: 100)) == -90)
    }
}
