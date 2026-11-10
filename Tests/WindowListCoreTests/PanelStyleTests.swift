import AppKit
import PropertyBased
import Testing
import WindowListCore

private let side = Gen.int(in: 30...800)

/// Alpha of each pixel of `PanelStyle.cornerMask()` drawn stretched to `width`×`height`, by x and y from the top left.
@MainActor
private func maskAlpha(width: Int, height: Int) throws -> (Int, Int) -> CGFloat {
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        "precondition: a \(width)×\(height) RGBA bitmap must be creatable")
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap), "precondition: bitmap must be drawable")
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    PanelStyle.cornerMask().draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return { x, y in bitmap.colorAt(x: x, y: y)?.alphaComponent ?? -1 }
}

@MainActor @Suite struct PanelStyleTests {
    @Test func cornerMaskClearsCorners() async {
        await propertyCheck(input: side, side) { width, height in
            await failOnThrow {
                let alpha = try maskAlpha(width: width, height: height)
                let corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
                #expect(
                    corners.allSatisfy { alpha($0.0, $0.1) == 0 },
                    "a \(width)×\(height) mask must be transparent at all four corners; got \(corners.map(alpha))"
                )
            }
        }
    }

    @Test func cornerMaskFillsEdgeMidpoints() async {
        await propertyCheck(input: side, side) { width, height in
            await failOnThrow {
                let alpha = try maskAlpha(width: width, height: height)
                let edges = [(width / 2, 0), (width / 2, height - 1), (0, height / 2), (width - 1, height / 2)]
                #expect(
                    edges.allSatisfy { alpha($0.0, $0.1) == 1 },
                    "a \(width)×\(height) mask must be opaque at each edge's midpoint; got \(edges.map(alpha))"
                )
            }
        }
    }

    @Test func cornerMaskFillsCenter() async {
        await propertyCheck(input: side, side) { width, height in
            await failOnThrow {
                let alpha = try maskAlpha(width: width, height: height)
                #expect(
                    alpha(width / 2, height / 2) == 1,
                    "a \(width)×\(height) mask must be opaque at its center; got \(alpha(width / 2, height / 2))"
                )
            }
        }
    }
}

/// `propertyCheck` discards thrown errors; this records them so a failed `#require` above fails the test.
private func failOnThrow(sourceLocation: SourceLocation = #_sourceLocation, _ body: () async throws -> Void) async {
    do {
        try await body()
    } catch is ExpectationFailedError {
        return
    } catch {
        Issue.record(error, "check threw instead of completing", sourceLocation: sourceLocation)
    }
}
