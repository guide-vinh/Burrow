import Foundation

/// How an installed app got onto the user's machine. Drives uninstall
/// hints (Mac App Store apps clean themselves; Homebrew casks should
/// be removed via `brew uninstall --cask`).
enum InstallSource: String, Codable, Hashable {
    case manual
    case macAppStore
    case homebrewCask
}
