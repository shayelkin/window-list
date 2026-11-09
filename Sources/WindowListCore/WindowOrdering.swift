import Foundation

public enum WindowOrdering {
    /// Case-, diacritic- and width-folded form used as the primary key. `localizedCaseInsensitiveCompare` is not
    /// transitive across scripts, so folded keys are compared by code point instead, which is a total order.
    public static func foldedKey(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Folded app name, raw app name, folded title, raw title, then window id — a strict total order.
    public static func areInIncreasingOrder(_ lhs: some WindowOrderable, _ rhs: some WindowOrderable) -> Bool {
        let lhsKey = (foldedKey(lhs.appName), lhs.appName, foldedKey(lhs.title), lhs.title)
        let rhsKey = (foldedKey(rhs.appName), rhs.appName, foldedKey(rhs.title), rhs.title)
        guard lhsKey == rhsKey else { return lhsKey < rhsKey }
        return lhs.id < rhs.id
    }

    public static func sorted<Entry: WindowOrderable>(_ entries: [Entry]) -> [Entry] {
        entries.sorted { areInIncreasingOrder($0, $1) }
    }
}
