import SwiftUI
import BezelCore

/// The first-launch guide: detect a running dsh, then either bind to it or
/// start a managed one — automatically (find it, install it if missing) or
/// with a command the user provides.
///
/// The steps map one-to-one onto the decisions the guide exists to collect:
///
/// 1. **Detect** — is a DSH background process running? (`DSHProcessScan`)
/// 2. Running → **choose**: bind the current process, or manage a new one.
///    Not running → straight to the managed choice, with a way back to bind
///    anyway (the scan can miss; a remote Host was never its business).
/// 3. **Bind** — the address and the token, from that process's own output.
/// 4. **Managed, automatic** — search for dsh and start it; when none is
///    installed, offer the npm install, then start what it installed.
/// 5. **Managed, manual** — the start command, run by the app and terminated
///    with it.
///
/// Every exit — connected, skipped — marks the guide done in the config
/// file, so it appears on a fresh install (or after "delete the file" resets
/// everything) and never otherwise.
struct OnboardingView: View {
    @Environment(AppState.self) private var app

    private enum Step {
        case detecting
        /// A process was found: bind it or start a managed one.
        case choice
        case bind
        /// Automatic or manual managed start.
        case managedChoice
        case auto
        case manual
    }

    private enum ManagedMode: String, CaseIterable, Identifiable {
        case automatic
        case manual

        var id: String { rawValue }
    }

    /// Where the automatic branch is: looking for dsh, or offering/installing.
    private enum AutoPhase: Equatable {
        case searching
        /// No usable dsh; the path is an `npm` to install it with, or none.
        case missing(npm: String?)
        case installing
        case failed(String)
    }

    /// Where a managed launch is: both managed steps render from this.
    private enum LaunchPhase: Equatable {
        case idle
        case starting
        case failed(String)
    }

    /// What the automatic branch's one search learned, kept for the install
    /// that may follow it (the merged environment comes from the same probe).
    private struct AutoSearch: Sendable {
        var loginShell: LoginShell?
        var report: DSHDiscovery.Report
        var npm: String?
    }

    @State private var step: Step = .detecting
    @State private var scan: DSHProcessScan.Report?
    @State private var mode: ManagedMode = .automatic
    @State private var bindAddress = ""
    @State private var bindToken = ""
    @State private var manualCommand = ""
    @State private var autoPhase: AutoPhase = .searching
    @State private var launchPhase: LaunchPhase = .idle
    @State private var autoSearch: AutoSearch?
    @State private var installer = OneShotCommand()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer.padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { beginDetection() }
        .onAppear { evaluateRunnerPhase(app.runner.phase) }
        .onChange(of: app.runner.phase) { _, phase in evaluateRunnerPhase(phase) }
        .onDisappear { installer.cancel() }
    }

    // MARK: - Chrome

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 6) {
            // One line, not three: the guide's top block is chrome, and every
            // point it spends vertically is a point the step's own content
            // does not get.
            HStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Text(titleText).font(.title3).fontWeight(.semibold)
            }
            Text(subtitleText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
        .padding(.bottom, 12)
        .padding(.horizontal, 40)
        .frame(maxWidth: 560)
    }

    private var titleText: String {
        switch step {
        case .detecting: app.text(.onboardingTitle)
        case .choice: app.text(.onboardingRunningTitle)
        case .bind: app.text(.onboardingBindTitle)
        case .managedChoice: app.text(.onboardingManagedTitle)
        case .auto: app.text(.onboardingAutoTitle)
        case .manual: app.text(.onboardingManualTitle)
        }
    }

    private var subtitleText: String {
        switch step {
        case .detecting: app.text(.onboardingSubtitle)
        case .choice: app.text(.onboardingRunningHelp)
        case .bind: app.text(.onboardingBindHelp)
        case .managedChoice: app.text(.onboardingManagedHelp)
        case .auto: app.text(.onboardingManagedAutoHelp)
        case .manual: app.text(.onboardingManagedManualHelp)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if let previous = previousStep {
                Button(app.text(.onboardingBack)) { goBack(to: previous) }
            }
            Spacer()
            Button(app.text(.onboardingSkip)) { app.completeOnboarding() }
                .disabled(installer.isRunning)
            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .detecting, .choice:
            EmptyView()
        case .bind:
            Button(app.text(.onboardingButtonBind)) { bindAndConnect() }
                .buttonStyle(.borderedProminent)
                .disabled(!DSHHost(baseURL: bindAddress).isValid)
        case .managedChoice:
            Button(app.text(.onboardingContinue)) { continueFromManagedChoice() }
                .buttonStyle(.borderedProminent)
        case .auto:
            switch autoPhase {
            case .missing(let npm):
                if npm != nil {
                    Button(app.text(.onboardingButtonInstall)) { installAndStart() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(app.text(.onboardingRetry)) { runAutoSearch() }
                }
            case .failed:
                Button(app.text(.onboardingRetry)) { installAndStart() }
            case .searching, .installing:
                EmptyView()
            }
        case .manual:
            switch launchPhase {
            case .idle:
                Button(app.text(.onboardingButtonStart)) { startManaged(command: manualCommand) }
                    .buttonStyle(.borderedProminent)
                    .disabled(manualCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case .starting:
                EmptyView()
            case .failed:
                Button(app.text(.onboardingRetry)) { startManaged(command: manualCommand) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .detecting: detectingContent
        case .choice: choiceContent
        case .bind: bindContent
        case .managedChoice: managedChoiceContent
        case .auto: autoContent
        case .manual: manualContent
        }
    }

    private var detectingContent: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(app.text(.onboardingDetecting)).foregroundStyle(.secondary)
        }
    }

    private var choiceContent: some View {
        VStack(spacing: 20) {
            if let scan { matchedProcesses(scan) }
            HStack(spacing: 12) {
                optionCard(
                    title: app.text(.onboardingChoiceBind),
                    help: app.text(.onboardingChoiceBindHelp),
                    icon: "link"
                ) { step = .bind }
                optionCard(
                    title: app.text(.onboardingChoiceManaged),
                    help: app.text(.onboardingChoiceManagedHelp),
                    icon: "arrow.up.circle"
                ) { step = .managedChoice }
            }
        }
        .padding(.horizontal, 40)
    }

    private var bindContent: some View {
        Form {
            TextField(
                app.text(.settingsFieldAddress),
                text: $bindAddress,
                prompt: Text("http://127.0.0.1:3080")
            )
            TextField(
                app.text(.settingsFieldToken),
                text: $bindToken,
                prompt: Text(app.text(.settingsFieldTokenPrompt))
            )
            Text(app.text(.onboardingBindHelp))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(maxWidth: 480)
    }

    private var managedChoiceContent: some View {
        VStack(spacing: 20) {
            if scan?.isRunning != true {
                VStack(spacing: 4) {
                    Text(app.text(.onboardingNotRunningTitle)).font(.headline)
                    Text(app.text(.onboardingNotRunningHelp))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ManagedMode.allCases) { candidate in
                    modeRow(candidate)
                }
            }
            .padding(.horizontal, 20)
            if scan?.isRunning != true {
                Button(app.text(.onboardingBindLater)) { step = .bind }
                    .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 40)
    }

    @ViewBuilder
    private var autoContent: some View {
        if launchPhase != .idle {
            launchContent
        } else {
            VStack(spacing: 16) {
                switch autoPhase {
                case .searching:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(app.text(.phaseLocating)).foregroundStyle(.secondary)
                    }
                case .missing(let npm):
                    if let npm {
                        VStack(spacing: 10) {
                            Text(app.text(.onboardingAutoNotFound)).font(.headline)
                            Text(app.text(.onboardingInstallHelp)).foregroundStyle(.secondary)
                            // The npm that was actually found, not a generic
                            // "npm": in a GUI app they are often not the same.
                            Text(app.text(.onboardingInstallWillRun, DSHInstall.displayCommand(npm: npm)))
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        VStack(spacing: 10) {
                            Text(app.text(.onboardingAutoNotFound)).font(.headline)
                            Text(app.text(.onboardingInstallNoNPM))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button(app.text(.onboardingSwitchManual)) { step = .manual }
                        }
                    }
                case .installing:
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(app.text(.onboardingInstalling)).foregroundStyle(.secondary)
                        installOutput
                    }
                case .failed(let message):
                    VStack(spacing: 10) {
                        Text(message).multilineTextAlignment(.center)
                        installOutput
                        Button(app.text(.onboardingSwitchManual)) { step = .manual }
                    }
                }
            }
            .padding(.horizontal, 40)
        }
    }

    private var manualContent: some View {
        VStack(spacing: 16) {
            if launchPhase == .idle {
                VStack(spacing: 10) {
                    TextField(
                        app.text(.onboardingManualCommand),
                        text: $manualCommand,
                        prompt: Text("dsh --profile web --port 0 --no-open")
                    )
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    Text(app.text(.launchCommandHelp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 480)
            } else {
                launchContent
            }
        }
        .padding(.horizontal, 40)
    }

    /// A managed launch in flight (or failed), shared by both managed steps.
    @ViewBuilder
    private var launchContent: some View {
        if launchPhase == .starting {
            VStack(spacing: 12) {
                ProgressView()
                Text(app.statusText).foregroundStyle(.secondary)
                // "Automatic" must not mean "silent about what it picked":
                // the search's own answer is shown while the child boots.
                // Only in the automatic step — a manual launch runs the
                // user's command, not whatever an earlier search found.
                if step == .auto, let chosen = autoSearch?.report.chosen {
                    Text(app.text(.onboardingAutoFound, chosen.executable))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        } else if case .failed(let message) = launchPhase {
            VStack(spacing: 10) {
                Text(app.text(.onboardingStartFailed)).font(.headline)
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                RunnerDiagnostics(lines: app.runnerDiagnostics)
                if step == .auto {
                    Button(app.text(.onboardingSwitchManual)) { step = .manual }
                }
            }
        }
    }

    /// The install's own output, when there is any to show.
    @ViewBuilder
    private var installOutput: some View {
        if !installer.lines.isEmpty {
            RunnerDiagnostics(lines: Array(installer.lines.suffix(12)))
        }
    }

    // MARK: - Pieces

    /// The command lines the scan matched, shown because "detected a dsh"
    /// must never be a black box: the user can see exactly what was found.
    private func matchedProcesses(_ scan: DSHProcessScan.Report) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(app.text(.onboardingMatchedProcesses))
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(scan.matches) { match in
                        Text(match.command)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 96)
        }
        .frame(maxWidth: 520)
    }

    private func optionCard(title: String, help: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3)
                Text(title).fontWeight(.semibold)
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 110)
        }
        .buttonStyle(.bordered)
    }

    private func modeRow(_ candidate: ManagedMode) -> some View {
        Button {
            mode = candidate
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: mode == candidate ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(mode == candidate ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.text(candidate == .automatic ? .onboardingManagedAuto : .onboardingManagedManual))
                        .fontWeight(.semibold)
                    Text(app.text(candidate == .automatic ? .onboardingManagedAutoHelp : .onboardingManagedManualHelp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Flow

    private var previousStep: Step? {
        switch step {
        case .detecting: nil
        case .choice: .detecting
        case .bind: scan?.isRunning == true ? .choice : .managedChoice
        case .managedChoice: scan?.isRunning == true ? .choice : .detecting
        case .auto, .manual: .managedChoice
        }
    }

    private func goBack(to previous: Step) {
        // Leaving a step abandons what it was doing: an install is stopped,
        // a launch's failure is forgotten.
        installer.cancel()
        launchPhase = .idle
        autoPhase = .searching
        if previous == .detecting {
            beginDetection()
        } else {
            step = previous
        }
    }

    private func beginDetection() {
        step = .detecting
        Task {
            let report = await Task.detached(priority: .userInitiated) { DSHProcessScan.scan() }.value
            scan = report
            // The bind form starts from the best guess at where the found
            // process is serving; the user pastes the real thing anyway.
            bindAddress = report.suggestedBaseURL
            step = report.isRunning ? .choice : .managedChoice
        }
    }

    private func continueFromManagedChoice() {
        switch mode {
        case .automatic:
            step = .auto
            runAutoSearch()
        case .manual:
            step = .manual
        }
    }

    /// The automatic branch's one search: find dsh, or an npm to install it
    /// with. Automatic means automatic — a found dsh is started straight
    /// away, which is what the user chose.
    private func runAutoSearch() {
        autoPhase = .searching
        launchPhase = .idle
        Task {
            let search = await Task.detached(priority: .userInitiated) { () -> AutoSearch in
                let shell = LoginShell.probe()
                let report = DSHDiscovery.locate(host: DSHHost(), loginShell: shell)
                let npm = report.chosen == nil
                    ? DSHDiscovery.findExecutable(named: "npm", loginShell: shell)
                    : nil
                return AutoSearch(loginShell: shell, report: report, npm: npm)
            }.value
            autoSearch = search
            guard step == .auto, launchPhase == .idle else { return }
            if search.report.chosen != nil {
                startManaged(command: "")
            } else {
                autoPhase = .missing(npm: search.npm)
            }
        }
    }

    private func installAndStart() {
        guard let npm = autoSearch?.npm else { return }
        autoPhase = .installing
        Task {
            let outcome = await installer.run(
                executable: npm,
                arguments: DSHInstall.arguments(),
                environment: DSHDiscovery.childEnvironment(loginShell: autoSearch?.loginShell),
                timeout: DSHInstall.timeout
            )
            guard step == .auto, case .installing = autoPhase, !outcome.cancelled, !installer.isRunning else { return }
            if outcome.succeeded {
                runAutoSearch()
            } else if outcome.timedOut {
                autoPhase = .failed(app.text(.failureTimedOut, String(Int(DSHInstall.timeout))))
            } else if let error = outcome.launchError {
                autoPhase = .failed(app.text(.failureLaunchFailed, error))
            } else {
                autoPhase = .failed(app.text(.onboardingInstallFailed, String(outcome.status ?? -1)))
            }
        }
    }

    private func startManaged(command: String) {
        guard let host = app.prepareManagedHost(command: command) else { return }
        launchPhase = .starting
        app.connect(to: host)
    }

    private func bindAndConnect() {
        guard app.bindRunningProcess(baseURL: bindAddress, token: bindToken) != nil else { return }
        app.completeOnboarding()
    }

    /// The runner's transitions, as they decide the guide: a launch that
    /// reached `running` ends it, a failed one is reported where it started.
    private func evaluateRunnerPhase(_ phase: LocalHostRunner.Phase) {
        switch phase {
        case .running:
            app.completeOnboarding()
        case .failed(let failure):
            if launchPhase == .starting {
                launchPhase = .failed(app.failureText(failure))
            }
        case .idle, .locating, .starting:
            break
        }
    }
}

/// The search report and the child's own output, as shown under a failed
/// managed launch — in the connect prompt and in the guide alike.
struct RunnerDiagnostics: View {
    let lines: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 560, maxHeight: 160)
    }
}
