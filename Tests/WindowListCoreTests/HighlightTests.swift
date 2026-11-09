import PropertyBased
import Testing
import WindowListCore

private let present = Generators.windowID.array(of: 0...20)

@Suite struct HighlightTests {
    @Test func reconcileKeepsPresentID() async {
        await propertyCheck(count: 500, input: present, Generators.windowID) { present, id in
            var highlight = Highlight(id)
            highlight.reconcile(with: present + [id])
            #expect(highlight.id == id, "highlight \(id) must survive when still listed in \(present + [id])")
        }
    }

    @Test func reconcileClearsAbsentID() async {
        await propertyCheck(count: 500, input: present, Generators.windowID) { present, id in
            var highlight = Highlight(id)
            highlight.reconcile(with: present.filter { $0 != id })
            #expect(highlight.id == nil, "highlight \(id) must clear when no longer listed")
        }
    }

    @Test func reconciledIDIsNilOrListed() async {
        await propertyCheck(count: 500, input: present, Generators.windowID.optional) { present, id in
            var highlight = Highlight(id)
            highlight.reconcile(with: present)
            #expect(
                highlight.id.map(present.contains) ?? true,
                "reconciled highlight \(String(describing: highlight.id)) must be nil or one of \(present)"
            )
        }
    }

    @Test func setReplacesHighlight() async {
        await propertyCheck(count: 500, input: Generators.windowID.optional, Generators.windowID.optional) { old, new in
            var highlight = Highlight(old)
            highlight.set(new)
            #expect(highlight.id == new, "set(\(String(describing: new))) must replace \(String(describing: old))")
        }
    }
}
