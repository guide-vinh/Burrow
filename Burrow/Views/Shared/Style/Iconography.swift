import Foundation

/// Maps a category icon string from CleanRules.json (lucide-style name)
/// to an SF Symbol available on macOS 12+.
enum Iconography {

    static func sfSymbol(for token: String) -> String {
        switch token {
        case "trash", "trash-2":        return "trash"
        case "doc-zipper":              return "doc.zipper"
        case "doc-text", "scroll-text": return "doc.text"
        case "alert-triangle":          return "exclamationmark.triangle"
        case "macwindow":               return "macwindow"
        case "eye":                     return "eye"
        case "iphone":                  return "iphone"
        case "globe", "compass":        return "globe"
        case "flame":                   return "flame"
        case "hammer":                  return "hammer"
        case "shippingbox", "package":  return "shippingbox"
        case "mug", "beer":             return "mug"
        case "message":                 return "message"
        case "music":                   return "music.note"
        case "video":                   return "video"
        case "photo":                   return "photo"
        case "settings":                return "gear"
        case "magnifyingglass":         return "magnifyingglass"
        case "network":                 return "network"
        case "tornado":                 return "tornado"
        case "sparkles":                return "sparkles"
        case "package-x":               return "xmark.bin"
        case "chart-pie":               return "chart.pie"
        case "activity":                return "waveform.path.ecg"
        case "badge-check":             return "checkmark.seal"
        case "code":                    return "chevron.left.forwardslash.chevron.right"
        default:                        return "questionmark.circle"
        }
    }
}
