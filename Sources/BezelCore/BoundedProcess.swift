import Foundation

/// Runs one short-lived child to completion under a deadline, and hands back
/// what it printed.
///
/// Three places needed exactly this — asking the login shell what it would run,
/// reading the `ps` listing, and probing a candidate `dsh --version` — and each
/// had grown its own copy of the same careful shape: spawn, drain the pipe on
/// another queue so a chatty child cannot fill it and wedge, poll for exit
/// against a deadline, terminate what overruns. The draining is the part worth
/// having in one place: leaving it out deadlocks only for the children that
/// print a lot, which is the hardest version of the bug to find.
///
/// Blocking by design, like the calls it replaced: every caller already runs it
/// off the main thread. It is deliberately not for the *managed* child, which
/// is long-lived, streams as it goes, and belongs to `LocalHostRunner`.
enum BoundedProcess {
    /// How a bounded run ended.
    struct Outcome: Sendable {
        var status: Int32
        /// Everything the child wrote to stdout, decoded as UTF-8.
        var output: String
    }

    /// Run `executable` and wait for it, up to `timeout`.
    ///
    /// `nil` means there is no answer to report: the child could not be
    /// launched, or it outlived the deadline and was terminated. Standard error
    /// goes to the null device — every caller here wants the answer, not the
    /// chatter.
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval
    ) -> Outcome? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe

        do { try process.run() } catch { return nil }

        // Drain concurrently: a child that prints more than the pipe buffer
        // holds would otherwise block on write while we wait for it to exit,
        // and neither side would ever move.
        let collected = Collected()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            collected.data = pipe.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { usleep(pollInterval) }
        if process.isRunning {
            process.terminate()
            return nil
        }
        guard drained.wait(timeout: .now() + drainGrace) == .success else { return nil }
        return Outcome(
            status: process.terminationStatus,
            output: String(decoding: collected.data, as: UTF8.self)
        )
    }

    /// How often the deadline is checked. Fine enough that a child which exits
    /// immediately is not made to look slow.
    private static let pollInterval: UInt32 = 20_000

    /// How long the reader gets after the child has already exited. The pipe is
    /// closed at that point, so this only covers handing the last bytes over.
    private static let drainGrace: TimeInterval = 2

    /// Carries the drained bytes across the dispatch boundary.
    private final class Collected: @unchecked Sendable {
        var data = Data()
    }
}
