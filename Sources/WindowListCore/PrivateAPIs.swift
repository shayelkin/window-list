import ApplicationServices
import CoreGraphics
import Foundation

// Private symbol declarations adapted from AltTab:
// https://github.com/lwouis/alt-tab-macos/blob/ec4f94a8b98a5b9df152af64f74aa4f9f811dd18/src/macos/api-wrappers/ApplicationServices.HIServices.framework.swift
// https://github.com/lwouis/alt-tab-macos/blob/ec4f94a8b98a5b9df152af64f74aa4f9f811dd18/src/macos/api-wrappers/SkyLight.framework.swift

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("_AXUIElementCreateWithRemoteToken")
private func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?

/// Unavailable in Swift (deprecated as of 10.9) but still exported; no public API maps a pid to a PSN.
@_silgen_name("GetProcessForPID")
private func _GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

@_silgen_name("_SLPSSetFrontProcessWithOptions")
private func _SLPSSetFrontProcessWithOptions(
    _ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ wid: CGWindowID, _ mode: UInt32
) -> CGError

@_silgen_name("SLPSPostEventRecordTo")
private func slpsPostEventRecordTo(
    _ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ bytes: UnsafeMutablePointer<UInt8>
) -> CGError

private typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
private func cgsMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func cgsCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

@_silgen_name("CGSCopySpacesForWindows")
private func cgsCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: Int, _ wids: CFArray) -> CFArray?

@_silgen_name("CGSCopyWindowsWithOptionsAndTags")
private func cgsCopyWindowsWithOptionsAndTags(
    _ cid: CGSConnectionID, _ owner: Int, _ spaces: CFArray, _ options: Int,
    _ setTags: UnsafeMutablePointer<Int>, _ clearTags: UnsafeMutablePointer<Int>
) -> CFArray?

/// Lists only windows ordered in on the given Spaces; setting bit 0 (e.g. 7) would add ordered-out windows.
private let orderedInWindowsOption = 2

/// `kCPSUserGenerated`: marks the front-switch as user-initiated (AltTab's `SLPSMode.userGenerated`).
private let frontProcessUserGenerated: UInt32 = 0x200

/// `CGSSpaceMask.all` in AltTab.
private let allSpacesMask = 7

enum PrivateAPI {
    static func windowID(of element: AXUIElement) -> WindowID? {
        var raw: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &raw) == .success else { return nil }
        return WindowID(raw)
    }

    static func element(from token: CFData) -> AXUIElement? {
        _AXUIElementCreateWithRemoteToken(token)?.takeRetainedValue()
    }

    static func managedDisplaySpaces() -> CFArray { cgsCopyManagedDisplaySpaces(cgsMainConnectionID()) }

    static func spaces(of window: WindowID) -> [UInt64] {
        let ids = [NSNumber(value: window.rawValue)] as CFArray
        guard let result = cgsCopySpacesForWindows(cgsMainConnectionID(), allSpacesMask, ids) as? [NSNumber] else {
            return []
        }
        return result.map(\.uint64Value)
    }

    static func orderedInWindows(on spaces: [UInt64]) -> [CGWindowID] {
        guard !spaces.isEmpty else { return [] }
        var setTags = 0
        var clearTags = 0
        let ids = spaces.map { NSNumber(value: $0) } as CFArray
        let result = cgsCopyWindowsWithOptionsAndTags(
            cgsMainConnectionID(), 0, ids, orderedInWindowsOption, &setTags, &clearTags)
        guard let windows = result as? [NSNumber] else { return [] }
        return windows.map(\.uint32Value)
    }

    static func processSerialNumber(for process: ProcessID) -> ProcessSerialNumber? {
        var psn = ProcessSerialNumber()
        guard _GetProcessForPID(process.rawValue, &psn) == noErr else { return nil }
        return psn
    }

    static func setFrontProcess(_ psn: inout ProcessSerialNumber, window: WindowID) -> CGError {
        _SLPSSetFrontProcessWithOptions(&psn, window.rawValue, frontProcessUserGenerated)
    }

    static func postMakeKey(_ psn: inout ProcessSerialNumber, record: MakeKeyEventRecord) -> CGError {
        var bytes = record.bytes
        var span = bytes.mutableSpan
        return span.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress, buffer.count == MakeKeyEventRecord.byteCount else {
                return .illegalArgument
            }
            return slpsPostEventRecordTo(&psn, base)
        }
    }
}
