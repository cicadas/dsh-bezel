import Foundation
import Observation

/// Runs one command to completion, keeping its output for display.
///
/// The guide's automatic install is the user's business happening on their
/// machine, so it must be visible while it runs: lines stream into `lines`
/// as the child prints them, and the exit status says how it ended. Lives in
/// BezelCore beside the other process owners so the app layer stays views.
@MainActor
@Observable
public final class OneShotCommand {
    /// How one run ended.
    public struct Outcome: Equatable, Sendable {
        /// The child's exit status, when it ran.
        public var status: Int32?
        /// Why it never ran, when it never ran.
        public var launchError: String?
        /// Whether the deadline ended it rather than the child finishing.
        public var timedOut: Bool
        /// Whether another `run` superseded this one before it ended.
        public var cancelled: Bool

        public var succeeded: Bool {
            launchError == nil && !timedOut && !cancelled && status == 0
        }
    }

    /// One run in flight: the child, its output pipe, and where to report its
    /// end. The identity is what keeps a superseded run's late callbacks —
    /// termination, output, deadline — from being charged to the run that
    /// replaced it.
    private struct Run {
        let id: UUID
        let process: Process
        /// Held so every end-state can detach the readability handler; a
        /// handler left installed keeps reading a pipe nobody reports from.
        let pipe: Pipe
        var continuation: CheckedContinuation<Outcome, Never>?
        var timedOut = false
    }

    /// Output lines, oldest first, capped like the runner's diagnostics.
    public private(set) var lines: [String] = []
    public private(set) var isRunning = false

    private var current: Run?

    public init() {}

    /// Run `executable` and await its end, streaming output into `lines`.
    ///
    /// A run still in flight is superseded: its awaiter is answered at once
    /// and its child terminated, so there is never more than one child to
    /// account for.
    @discardableResult
    public func run(
        executable: String,
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval
    ) async -> Outcome {
        supersede()
        lines = []
        isRunning = true

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let id = UUID()
        current = Run(id: id, process: process, pipe: pipe, continuation: nil)
        process.terminationHandler = { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, self.current?.id == id else { return }
                let timedOut = self.current?.timedOut ?? false
                self.finish(id: id, outcome: Outcome(
                    status: finished.terminationStatus,
                    launchError: nil,
                    timedOut: timedOut,
                    cancelled: false
                ))
            }
        }
        do {
            try process.run()
        } catch {
            current = nil
            isRunning = false
            detachPipe(pipe)
            return Outcome(status: nil, launchError: error.localizedDescription, timedOut: false, cancelled: false)
        }

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in self?.ingest(text, id: id) }
        }

        // The deadline only ever terminates; the termination handler is what
        // reports, so the continuation resumes exactly once per run.
        Task { [weak self, id] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            self?.deadlinePassed(id: id)
        }

        return await withCheckedContinuation { continuation in
            current?.continuation = continuation
        }
    }

    /// Terminate the run in flight, if any; its `run` then returns with the
    /// termination status.
    public func cancel() {
        guard let run = current else { return }
        if run.process.isRunning { run.process.terminate() }
    }

    // MARK: - Run bookkeeping

    /// Answer the awaiter of the run in flight, if any, and stop its child.
    private func supersede() {
        guard let previous = current else { return }
        current = nil
        detachPipe(previous.pipe)
        if previous.process.isRunning { previous.process.terminate() }
        previous.continuation?.resume(returning: Outcome(
            status: nil, launchError: nil, timedOut: false, cancelled: true
        ))
        isRunning = false
    }

    private func deadlinePassed(id: UUID) {
        guard let run = current, run.id == id else { return }
        current?.timedOut = true
        if run.process.isRunning { run.process.terminate() }
    }

    /// Report `outcome` to the awaiting caller, exactly once per run.
    private func finish(id: UUID, outcome: Outcome) {
        guard current?.id == id else { return }
        let continuation = current?.continuation
        if let pipe = current?.pipe { detachPipe(pipe) }
        current = nil
        isRunning = false
        continuation?.resume(returning: outcome)
    }

    /// Stop reading a pipe nobody will report from.
    ///
    /// The same care `LocalHostRunner.detachPipe` takes, and for the same
    /// reason: the handler clears itself only on EOF, and EOF does not come
    /// when the child leaves a grandchild holding the inherited stdout — which
    /// is exactly what `npm install` does. Without this the finished run keeps
    /// its pipe's read end open for the object's whole idle life (measured:
    /// two descriptors instead of one).
    private func detachPipe(_ pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = nil
    }

    private func ingest(_ text: String, id: UUID) {
        guard current?.id == id else { return }
        lines.append(contentsOf: text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
        if lines.count > 500 { lines.removeFirst(lines.count - 500) }
    }
}
