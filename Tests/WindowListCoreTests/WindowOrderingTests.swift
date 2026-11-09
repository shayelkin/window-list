import Foundation
import PropertyBased
import Testing
import WindowListCore

private struct Item: WindowOrderable, Sendable, CustomStringConvertible {
    let id: WindowID
    let appName: String
    let title: String

    var description: String { "(\(appName)|\(title)|\(id.rawValue))" }
}

/// Items with unique ids (as window ids are), random app names and titles.
private let items = zip(Generators.text, Generators.text).array(of: 0...30).map { pairs in
    pairs.enumerated().compactMap { index, pair in
        WindowID(UInt32(index + 1)).map { Item(id: $0, appName: pair.0, title: pair.1) }
    }
}

private let item = zip(Generators.windowID, Generators.text, Generators.text).map {
    Item(id: $0, appName: $1, title: $2)
}

private func before(_ lhs: Item, _ rhs: Item) -> Bool { WindowOrdering.areInIncreasingOrder(lhs, rhs) }

@Suite struct WindowOrderingTests {
    @Test func sortIsPermutation() async {
        await propertyCheck(count: 500, input: items) { items in
            let sorted = WindowOrdering.sorted(items)
            #expect(
                sorted.map(\.id).sorted() == items.map(\.id).sorted(),
                "sorting must keep exactly the input windows: \(items) -> \(sorted)"
            )
        }
    }

    @Test func outputIsSorted() async {
        await propertyCheck(count: 500, input: items) { items in
            let sorted = WindowOrdering.sorted(items)
            let inversions = zip(sorted, sorted.dropFirst()).filter { before($1, $0) }
            #expect(inversions.isEmpty, "adjacent pairs must be in order; inversions \(inversions)")
        }
    }

    @Test func orderIndependentOfInputShuffle() async {
        await propertyCheck(count: 500, input: items, Gen.uint64()) { items, seed in
            var rng = SeededGenerator(seed: seed)
            let shuffled = items.shuffled(using: &rng)
            #expect(
                WindowOrdering.sorted(shuffled).map(\.id) == WindowOrdering.sorted(items).map(\.id),
                "result must not depend on input order: \(items) vs shuffled \(shuffled)"
            )
        }
    }

    @Test func comparatorIsIrreflexive() async {
        await propertyCheck(count: 500, input: item) { item in
            #expect(!before(item, item), "an item must not sort before itself: \(item)")
        }
    }

    @Test func comparatorIsAsymmetric() async {
        await propertyCheck(count: 500, input: item, item) { lhs, rhs in
            #expect(!(before(lhs, rhs) && before(rhs, lhs)), "\(lhs) and \(rhs) must not each sort before the other")
        }
    }

    @Test func comparatorIsTransitive() async {
        await propertyCheck(count: 500, input: item, item, item) { a, b, c in
            guard before(a, b), before(b, c) else { return }
            #expect(before(a, c), "\(a) < \(b) < \(c) must imply \(a) < \(c)")
        }
    }

    @Test func distinctWindowsAreTotallyOrdered() async {
        await propertyCheck(count: 500, input: item, item) { lhs, rhs in
            guard lhs.id != rhs.id else { return }
            #expect(before(lhs, rhs) || before(rhs, lhs), "distinct windows \(lhs), \(rhs) must be comparable")
        }
    }

    @Test func appNamesWithEqualFoldedKeyAreContiguous() async {
        await propertyCheck(count: 500, input: items) { items in
            let keys = WindowOrdering.sorted(items).map { WindowOrdering.foldedKey($0.appName) }
            let runs = keys.indices.filter { $0 == keys.startIndex || keys[$0] != keys[$0 - 1] }.map { keys[$0] }
            #expect(Set(runs).count == runs.count, "each app's windows must be contiguous; split groups in \(keys)")
        }
    }

    @Test func foldedKeyIgnoresCase() async {
        await propertyCheck(count: 500, input: Generators.text) { text in
            #expect(
                WindowOrdering.foldedKey(text.uppercased()) == WindowOrdering.foldedKey(text.lowercased()),
                "folded key must be case-insensitive for \"\(text)\""
            )
        }
    }
}
