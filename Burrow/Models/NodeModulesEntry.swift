import Foundation

/// One discovered `node_modules` directory. Produced by
/// `NodeModulesScanner`. Pure data — UI sorts/filters via the published
/// `[NodeModulesEntry]` array on the view-model.
struct NodeModulesEntry: Hashable, Identifiable {
    /// Absolute path to the `node_modules` directory itself.
    let url: URL

    /// Parent project directory (the dir that *contains* `node_modules`).
    let parentURL: URL

    /// Display label for the project. Last path component of `parentURL`,
    /// falling back to `parentURL.path` if empty.
    let parentName: String

    /// Recursive byte count of `node_modules`.
    let totalBytes: Int64

    /// Modification date of the `node_modules` directory itself —
    /// reflects the last `npm install` / build mutation.
    let nodeModulesMtime: Date

    /// Newest modification date among the parent project's *direct*
    /// children, excluding `node_modules`. Reflects when the project
    /// was last actively edited (file save, build output, git checkout).
    let parentMtime: Date

    var id: URL { url }
}
