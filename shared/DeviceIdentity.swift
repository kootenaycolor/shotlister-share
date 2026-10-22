import Foundation

#if canImport(IOKit)
import IOKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// **What a device calls itself, and which machine that name belongs to.**
///
/// Ref 186. These are two different facts and the difference is the whole bug.
///
/// The **name** is what goes on every change a device writes, and sync rests on
/// no two devices sharing one: when they do, a change each makes in the same
/// millisecond produces the same stamp, and the second is dropped as a
/// duplicate of the first. Nothing is said and there is no way to notice
/// afterwards. Three ways that could happen, all of them real:
///
/// - The Mac and the phone remember their names in system preferences, and
///   preferences are exactly what Migration Assistant copies when a new Mac is
///   set up from an old one. Two Macs, one name.
/// - The Drive bridge had its name written into the program, so a second copy
///   anywhere was a guaranteed collision.
/// - Claude's server worked its name out the same way on every machine.
///
/// The **machine** is the hardware itself — on a Mac the platform UUID, on the
/// phone the vendor identifier. It is not remembered anywhere, so there is
/// nothing for Migration Assistant to copy, and that is what makes it able to
/// answer the question the name cannot: *are these two devices, or one?*
///
/// Both apps and the bridge compile this file, so all three answer it the same
/// way.
enum DeviceIdentity {

    /// **Which machine this is.** Hand it to `sl_open_as_installed`, which
    /// leaves it beside the project's diaries and reads everybody else's; two
    /// machines claiming one name arrive back as `project.deviceClash`.
    ///
    /// Worked out once per run. Zero would mean "no opinion", so a machine that
    /// will not say what it is gets a number anyway rather than opting out of
    /// the check — but it comes from the hardware whenever the hardware will
    /// answer.
    static let installation: UInt64 = number(of: hardwareIdentifier())

    /// **A name for something that has nowhere to remember one**, worked out
    /// from the machine rather than made up and written down.
    ///
    /// The bridge and Claude's server both run without preferences of their
    /// own. Deriving from the hardware gives each of them a name that is the
    /// same every run on this machine and different on any other, which is
    /// exactly what a remembered random number was supposed to achieve and
    /// what a written-in constant never could.
    ///
    /// `role` separates the several programs that may run on one machine. The
    /// bridge and the Mac app are two writers and must not share a name any
    /// more than two Macs may.
    static func name(role: String) -> UInt64 {
        let derived = number(of: "\(hardwareIdentifier())/\(role)")
        // Zero and one both mean something else to the engine — no opinion, and
        // the old single-device default. Neither is a name.
        return derived < 2 ? derived &+ 2 : derived
    }

    // ---- the hardware ---------------------------------------------------

    /// The machine, as the operating system will say it.
    ///
    /// Falls back to the host name, which is weak — two machines can share one
    /// — but is still better than a constant, and only ever reached on a
    /// platform that is neither macOS nor iOS.
    private static func hardwareIdentifier() -> String {
        #if os(macOS)
        if let uuid = platformUUID() { return "mac:\(uuid)" }
        #elseif os(iOS)
        if let vendor = UIDevice.current.identifierForVendor?.uuidString {
            return "ios:\(vendor)"
        }
        #endif
        return "host:\(ProcessInfo.processInfo.hostName)"
    }

    #if os(macOS)
    /// The Mac's platform UUID, straight out of the I/O registry.
    ///
    /// This is the number Migration Assistant cannot bring with it, which is
    /// the entire reason for reading it rather than remembering something.
    private static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard
            let property = IORegistryEntryCreateCFProperty(
                service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)
        else { return nil }
        return property.takeRetainedValue() as? String
    }
    #endif

    // ---- text to a number -----------------------------------------------

    /// FNV-1a, 64 bits. Not a security choice — nothing here is a secret — but
    /// a stable one: the same text gives the same number on every machine, on
    /// every build, forever, which a hash the standard library chooses for us
    /// deliberately does not.
    private static func number(of text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in Array(text.utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
