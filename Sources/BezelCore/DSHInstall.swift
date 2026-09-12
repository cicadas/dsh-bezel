import Foundation

/// How the guide installs dsh when the machine does not have one.
///
/// dsh is an npm package (`@deepseek-ai/dsh`), so the automatic installation
/// is an `npm install -g`: it puts `dsh` on the global bin directory, which is
/// exactly where `DSHDiscovery` looks, so a successful install needs no
/// further wiring — the next search finds it.
public enum DSHInstall {
    /// The npm package that provides the `dsh` command.
    public static let packageName = "@deepseek-ai/dsh"

    /// The arguments that install it globally, paired with an `npm` found by
    /// `DSHDiscovery.findExecutable(named:)`.
    public static func arguments() -> [String] {
        ["install", "-g", packageName]
    }

    /// The same invocation as text to show next to the button that runs it,
    /// so "install automatically" never means "install something unseen".
    public static var displayCommand: String {
        "npm install -g " + packageName
    }

    /// The invocation as it will actually be run, naming the `npm` that was
    /// found. A GUI app's `npm` is often not the one the user's terminal has,
    /// so the full path is the only version of this line that is true.
    public static func displayCommand(npm: String) -> String {
        ([npm] + arguments()).joined(separator: " ")
    }

    /// How long the install gets. dsh pulls a large dependency tree; on a
    /// slow link this genuinely takes minutes.
    public static let timeout: TimeInterval = 300
}
