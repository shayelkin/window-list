import ApplicationServices

public enum CloseError: Error, Equatable, Sendable {
    case activationFailed(ActivationError)
    case closeButtonUnavailable(AXFailure)
    case pressFailed(AXFailure)
}

public enum WindowCloser {
    /// Closes `entry`'s window by pressing its close button, so the app can still ask to save changes.
    /// An unresolved window has no AX element until it is focused, so it is activated first, switching Space.
    public static func close(_ entry: WindowEntry) async throws(CloseError) {
        let window: AXWindow
        switch entry.access {
        case .resolved(let known):
            window = known
        case .unresolved:
            do throws(ActivationError) {
                window = try await WindowActivator.activate(entry)
            } catch {
                throw .activationFailed(error)
            }
        }
        let button: AXElement
        do throws(AXFailure) {
            button = try window.element.element(kAXCloseButtonAttribute)
        } catch {
            throw .closeButtonUnavailable(error)
        }
        do throws(AXFailure) {
            try button.perform(kAXPressAction)
        } catch {
            throw .pressFailed(error)
        }
    }
}
