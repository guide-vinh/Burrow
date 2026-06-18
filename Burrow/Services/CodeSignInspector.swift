import Foundation
import Security
import os

private let logger = Logger(subsystem: "fun.burrow", category: "CodeSignInspector")

/// Inspects an app bundle's code signature using the native Security
/// framework (no subprocess). Reports whether the signature verifies, who
/// signed it, whether it's ad-hoc / Apple / Developer ID — the signals that
/// separate a legitimately distributed app from a re-signed or tampered one.
/// Every call is independent, so calls run safely in parallel.
enum CodeSignInspector {

    /// `kSecCodeSignatureAdhoc` — the ad-hoc bit in the code-signing flags.
    private static let adHocFlag: UInt32 = 0x0002

    /// Validate the signature + cert chain only — skip hashing every resource
    /// in the bundle. Full validation re-hashes the whole app (very slow for
    /// large apps); basic validation still catches unsigned / ad-hoc / broken
    /// signatures, which is what the verdict needs.
    private static let basicFlags = SecCSFlags(rawValue: kSecCSBasicValidateOnly)

    static func inspect(_ bundleURL: URL) -> SignatureInfo {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            return SignatureInfo.unknown
        }

        // 1. Does the signature verify?
        let validity = SecStaticCodeCheckValidity(code, basicFlags, nil)
        var info = SignatureInfo(
            isValid: validity == errSecSuccess,
            isUnsigned: validity == errSecCSUnsigned,
            isAdHoc: false,
            isApple: false,
            isNotarized: nil,
            developer: nil,
            teamID: nil
        )

        // 2. Signing details — cheap; reads the signature blob, not resources.
        var signingDict: CFDictionary?
        if SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &signingDict) == errSecSuccess,
           let dict = signingDict as? [String: Any] {

            if let flags = dict[kSecCodeInfoFlags as String] as? UInt32 {
                info.isAdHoc = (flags & adHocFlag) != 0
            }
            info.teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String

            if let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate],
               let leaf = certs.first,
               let cn = commonName(of: leaf) {
                info.developer = prettyDeveloper(cn)
                // A Developer ID cert means notarization is required for
                // distribution — a reasonable "from a real developer" proxy.
                if cn.hasPrefix("Developer ID Application:") { info.isNotarized = true }
            }
        }

        // 3. Apple-signed system software? (one cheap requirement check)
        info.isApple = satisfies(code, requirement: "anchor apple")

        return info
    }

    // MARK: - Helpers

    /// True if `code` satisfies the designated-requirement string (basic check).
    private static func satisfies(_ code: SecStaticCode, requirement: String) -> Bool {
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess,
              let requirement = req else { return false }
        return SecStaticCodeCheckValidity(code, basicFlags, requirement) == errSecSuccess
    }

    private static func commonName(of cert: SecCertificate) -> String? {
        var cn: CFString?
        guard SecCertificateCopyCommonName(cert, &cn) == errSecSuccess else { return nil }
        return cn as String?
    }

    /// "Developer ID Application: Google LLC (EQHXZ8M8AV)" → "Google LLC".
    private static func prettyDeveloper(_ commonName: String) -> String? {
        var name = commonName
        for prefix in ["Developer ID Application: ", "Apple Distribution: ", "Mac Developer: ", "3rd Party Mac Developer Application: ", "Apple Mac OS Application Signing"] {
            if name.hasPrefix(prefix) { name.removeFirst(prefix.count) }
        }
        if let open = name.lastIndex(of: "("), name.hasSuffix(")") {
            name = String(name[..<open]).trimmingCharacters(in: .whitespaces)
        }
        return name.isEmpty ? nil : name
    }
}
