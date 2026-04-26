import AppKit
import Foundation
import os

/// Probes whether the current process has Full Disk Access (FDA) by
/// attempting to read a known FDA-gated path. Routes the user to
/// System Settings on denial.
enum FullDiskAccess {

    private static let logger = Logger(subsystem: "fun.burrow", category: "FullDiskAccess")

    /// Default probe path. SPEC section 4 names this file as a reliable
    /// FDA tripwire — Safari's CloudTabs db sits inside ~/Library/Safari
    /// which the OS gates behind FDA.
    static var defaultProbe: URL {
        URL(fileURLWithPath: (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Safari/CloudTabs.db"))
    }

    /// Returns true if the current process can read `url`, false if the
    /// kernel returned EPERM/EACCES (FDA not granted) or if the file is
    /// missing (ENOENT — caller may treat as "Safari uninstalled, try
    /// another tripwire").
    static func probe(at url: URL = defaultProbe) -> Bool {
        let path = url.path
        let fd = open(path, O_RDONLY)

        if fd == -1 {
            let err = errno
            switch err {
            case EPERM, EACCES:
                logger.debug("FDA probe denied at \(path, privacy: .private)")
            case ENOENT:
                logger.info("FDA probe path missing at \(path, privacy: .private)")
            default:
                logger.error("FDA probe unexpected errno \(err, privacy: .public) at \(path, privacy: .private)")
            }
            return false
        }

        // Actually attempt to read 1 byte — some sandboxes return success
        // on open(2) but EPERM on read(2).
        var byte: UInt8 = 0
        let bytesRead = read(fd, &byte, 1)
        let readErrno = errno
        close(fd)

        if bytesRead == -1 {
            switch readErrno {
            case EPERM, EACCES:
                logger.debug("FDA probe denied at \(path, privacy: .private)")
            case ENOENT:
                logger.info("FDA probe path missing at \(path, privacy: .private)")
            default:
                logger.error("FDA probe unexpected errno \(readErrno, privacy: .public) at \(path, privacy: .private)")
            }
            return false
        }

        return true
    }

    /// Opens System Settings → Privacy & Security → Full Disk Access
    /// via the x-apple.systempreferences URL scheme.
    static func openSystemSettings() {
        logger.info("Opening Full Disk Access settings")
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}
