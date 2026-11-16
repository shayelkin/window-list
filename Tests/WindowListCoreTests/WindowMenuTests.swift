import PropertyBased
import Testing
import WindowListCore

@Suite struct WindowMenuTests {
    @Test func itemsAreSwitchToThenClose() {
        #expect(
            WindowMenuAction.allCases == [.switchTo, .close],
            "the window menu must list exactly Switch To, then Close; got \(WindowMenuAction.allCases)")
    }

    @Test func titlesMatchActions() {
        #expect(
            WindowMenuAction.allCases.map(\.title) == ["Switch To", "Close"],
            "the window menu titles must read Switch To, Close; got \(WindowMenuAction.allCases.map(\.title))")
    }

    @Test func distinctActionsHaveDistinctTitles() async {
        let action = Gen.element(of: WindowMenuAction.allCases).compactMap { $0 }
        await propertyCheck(input: action, action) { a, b in
            #expect(
                (a == b) == (a.title == b.title),
                "\(a) and \(b) must share a title only when they are the same action; got \(a.title), \(b.title)")
        }
    }
}
