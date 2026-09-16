import Foundation

/// The languages the app ships with.
///
/// This is an in-app setting, not a system preference: the UI language stays
/// English until the user picks another one in Settings, whatever macOS itself
/// is set to. That also keeps the wording stable for everyone reading a bug
/// report or a screenshot.
public enum AppLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case french = "fr"
    case german = "de"
    case spanish = "es"

    public var id: String { rawValue }

    /// Each language names itself, the way language pickers do.
    public var displayName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        }
    }

    public static let fallback = AppLanguage.english
}

/// Every message the app can show.
///
/// The translations live side by side in exhaustive switches below, so a
/// message cannot ship half-translated: forgetting one is a compile error,
/// not a Chinese string that quietly shows up in an English UI.
public enum Message: CaseIterable, Sendable {
    // Host bookmarks
    case seedHostName
    case newHostName
    case untitledHost
    case invalidAddress

    // Status line and managed-host phases
    case statusNotConnected
    case statusLoading
    case statusConnected
    case phaseLocating
    case phaseStarting
    case phaseCheckingPort

    // Managed-host failures
    case failureNoDSH
    case failureLaunchFailed
    case failureExited
    case failureExitedBeforeStart
    case failureTimedOut

    // Discovery diagnostics
    case originHostSetting
    case originEnvironmentOverride
    case originLoginShell
    case originAppPath
    case originWellKnown
    case attemptSelected
    case attemptNotExecutable
    case attemptDidNotRun
    case attemptSkipped
    case diagnosticChosen
    case diagnosticNoneFound
    case diagnosticChildPATH

    // Toolbar and connect prompt
    case toolbarSelectHost
    case toolbarReload
    case toolbarOpenInBrowser
    case toolbarDisconnect
    case menuManageHosts
    case buttonConnectSelected
    case buttonStartDSH
    case buttonRestartDSH
    case buttonCheckHostSettings
    case connectPromptTitle
    case portConflictTitle
    case portConflictMessage
    case portConflictBind
    case portConflictCancel

    // Find in page
    case menuFindTitle
    case menuFind
    case menuFindNext
    case menuFindPrevious
    case menuUseSelectionForFind
    case findMatchesFound

    // Settings
    case settingsTabHosts
    case settingsTabGeneral
    case settingsLanguage
    case settingsLanguageHelp
    case settingsLanguageRestartNote
    case settingsRestartNow
    case settingsSelectOrCreate
    case settingsNewHost
    case settingsRemoveHost
    case settingsFieldName
    case settingsFieldAddress
    case settingsFieldToken
    case settingsFieldTokenPrompt
    case settingsTokenHelp
    case settingsToggleManaged
    case settingsFieldExtraArguments
    case settingsFieldDSHPath
    case settingsFieldDSHPathPrompt
    case settingsManagedHelp
    case settingsButtonConnect
    case settingsInvalidAddress
    case settingsConfigFile
    case settingsConfigHelp
    case settingsWriteFailed
    case settingsUnreadableData
    case settingsNewerFile

    // WebView
    case errorCredentialRejected

    // Notifications
    case notificationAttentionApproval
    case notificationAttentionQuestion
    case notificationAttentionPlan
    case notificationTaskFinished
    case settingsNotifications
    case settingsNotificationsHelp
    case settingsChannelHealthy
    case settingsChannelUnauthorized
    case settingsChannelReconnecting
    case settingsPageRefresh
    case settingsPageRefreshHelp

    // First-launch guide
    case onboardingTitle
    case onboardingSubtitle
    case onboardingSkip
    case onboardingBack
    case onboardingDetecting
    case onboardingRunningTitle
    case onboardingRunningHelp
    case onboardingNotRunningTitle
    case onboardingNotRunningHelp
    case onboardingMatchedProcesses
    case onboardingChoiceBind
    case onboardingChoiceBindHelp
    case onboardingChoiceManaged
    case onboardingChoiceManagedHelp
    case onboardingBindLater
    case onboardingBindTitle
    case onboardingBindHelp
    case onboardingButtonBind
    case onboardingManagedTitle
    case onboardingManagedHelp
    case onboardingManagedAuto
    case onboardingManagedAutoHelp
    case onboardingManagedManual
    case onboardingManagedManualHelp
    case onboardingContinue
    case onboardingAutoTitle
    case onboardingAutoFound
    case onboardingAutoNotFound
    case onboardingInstallHelp
    case onboardingInstallWillRun
    case onboardingButtonInstall
    case onboardingInstalling
    case onboardingInstallFailed
    case onboardingInstallNoNPM
    case onboardingButtonStart
    case onboardingStartFailed
    case onboardingRetry
    case onboardingSwitchManual
    case onboardingManualTitle
    case onboardingManualCommand
    case launchCommandHelp
    case onboardingBindHostName
    case settingsFieldLaunchCommand
    case settingsFieldLaunchCommandPrompt

    // Tabs
    case tabNewTab
    case tabClose
}

/// The text of one message in one language, with `{1}`, `{2}`… filled in.
///
/// Positional placeholders instead of `String(format:)`: translations stay
/// free of printf pitfalls, and a translation is free to reorder arguments.
public struct Localization: Equatable, Sendable {
    public var language: AppLanguage

    public init(language: AppLanguage = .fallback) {
        self.language = language
    }

    public func text(_ message: Message, _ arguments: String...) -> String {
        Localization.substitute(message.template(in: language), arguments)
    }

    public func text(_ message: Message, _ arguments: [String]) -> String {
        Localization.substitute(message.template(in: language), arguments)
    }

    static func substitute(_ template: String, _ arguments: [String]) -> String {
        var result = template
        for (index, argument) in arguments.enumerated() {
            result = result.replacingOccurrences(of: "{\(index + 1)}", with: argument)
        }
        return result
    }
}

extension Message {
    func template(in language: AppLanguage) -> String {
        switch language {
        case .english: english
        case .simplifiedChinese: simplifiedChinese
        case .traditionalChinese: traditionalChinese
        case .japanese: japanese
        case .french: french
        case .german: german
        case .spanish: spanish
        }
    }

    /// English, which is also the default UI language.
    var english: String {
        switch self {
        case .seedHostName: "Local dsh"
        case .newHostName: "New Host"
        case .untitledHost: "Untitled Host"
        case .invalidAddress: "Invalid Host address: {1}"

        case .statusNotConnected: "Not connected"
        case .statusLoading: "Loading…"
        case .statusConnected: "Connected"
        case .phaseLocating: "Looking for a usable dsh…"
        case .phaseStarting: "Starting local dsh…"
        case .phaseCheckingPort: "Checking whether a dsh already serves this port…"

        case .failureNoDSH: "No usable dsh found (tried {1} locations; see the output below)"
        case .failureLaunchFailed: "Could not launch dsh: {1}"
        case .failureExited: "dsh exited (status {1})"
        case .failureExitedBeforeStart: "dsh failed to start (status {1})"
        case .failureTimedOut: "dsh did not start within {1} seconds"

        case .originHostSetting: "Host setting"
        case .originEnvironmentOverride: "BEZEL_DSH_PATH"
        case .originLoginShell: "login shell"
        case .originAppPath: "app PATH"
        case .originWellKnown: "common install locations"
        case .attemptSelected: "selected"
        case .attemptNotExecutable: "missing or not executable"
        case .attemptDidNotRun: "present, but `--version` cannot run (usually no node or npm on PATH)"
        case .attemptSkipped: "not tried — the search's time budget ran out first"
        case .diagnosticChosen: "dsh: {1} (source: {2})"
        case .diagnosticNoneFound: "No usable dsh found; every location below was tried"
        case .diagnosticChildPATH: "Child PATH:"

        case .toolbarSelectHost: "Select Host"
        case .toolbarReload: "Reload"
        case .toolbarOpenInBrowser: "Open in Browser"
        case .toolbarDisconnect: "Disconnect"
        case .menuManageHosts: "Manage Hosts…"
        case .buttonConnectSelected: "Connect Selected Host"
        case .buttonStartDSH: "Start dsh"
        case .buttonRestartDSH: "Restart dsh"
        case .buttonCheckHostSettings: "Check Host Settings"
        case .connectPromptTitle: "Select a dsh Host to connect to"
        case .portConflictTitle: "Port Already Served by a Running dsh"
        case .portConflictMessage: "A dsh is already running on port {1} ({2}). You can bind to it instead; this app will not start another one."
        case .portConflictBind: "Bind to the Running dsh"
        case .portConflictCancel: "Cancel"

        case .menuFindTitle: "Find"
case .menuFind: "Find…"
        case .menuFindNext: "Find Next"
        case .menuFindPrevious: "Find Previous"
        case .menuUseSelectionForFind: "Use Selection for Find"
        case .findMatchesFound: "{1} found"

        case .settingsTabHosts: "Hosts"
        case .settingsTabGeneral: "General"
        case .settingsLanguage: "Language"
        case .settingsLanguageHelp: "Applies to this app's own interface. It does not change the language of the Host's Web UI, which is the Host's own setting."
        case .settingsLanguageRestartNote: "The menu bar picks up the new language at the next launch; everything else switches immediately."
        case .settingsRestartNow: "Restart Now"
        case .settingsSelectOrCreate: "Select or create a Host"
        case .settingsNewHost: "New Host"
        case .settingsRemoveHost: "Remove Host"
        case .settingsFieldName: "Name"
        case .settingsFieldAddress: "Address"
        case .settingsFieldToken: "Launch token (optional)"
        case .settingsFieldTokenPrompt: "the ?token=… from the startup output"
        case .settingsTokenHelp: "The token is only used once, to mint the 30-day signed cookie. If the cookie expires, or the Host process is replaced, paste the full address from `dsh web`'s output again."
        case .settingsToggleManaged: "Start a local dsh for this Host"
        case .settingsFieldExtraArguments: "Extra arguments"
        case .settingsFieldDSHPath: "dsh executable path"
        case .settingsFieldDSHPathPrompt: "leave empty to search automatically"
        case .settingsManagedHelp: "Runs `dsh --profile <profile> --port 0 --no-open`: the system picks the port and the URL is read from the child's output. An app launched from Finder cannot see your terminal's PATH, so discovery asks the login shell and probes every candidate with `--version`; if none of them works, put the output of `command -v dsh` in the field above."
        case .settingsButtonConnect: "Connect to This Host"
        case .settingsInvalidAddress: "Invalid address"
        case .settingsConfigFile: "Config file"
        case .settingsConfigHelp: "Bookmarks, the selected Host and the language all live in this file. It is read at launch, so edits made while the app is closed take effect the next time it opens."
        case .settingsWriteFailed: "Could not write the config file: {1}"
        case .settingsUnreadableData: "The config file cannot be decoded, so the default Host is in use. The file itself has not been overwritten."
        case .settingsNewerFile: "This config file was written by a newer version of the app (version {1}). It is being used as far as this version understands it, but nothing is written back, so changes made here will not be kept."

        case .errorCredentialRejected: "The Host rejected this credential: the token is invalid and no usable cookie is present"

        case .notificationAttentionApproval: "Approval needed: a tool call is waiting for your decision"
        case .notificationAttentionQuestion: "The Host asked a question and is waiting for your answer"
        case .notificationAttentionPlan: "A plan is waiting for your review"
        case .notificationTaskFinished: "The task has finished"
        case .settingsNotifications: "Notifications"
        case .settingsNotificationsHelp: "A macOS notification when the Host is waiting for you — a tool approval, a question, a plan review, in any session — and when a running task finishes. Whatever state this app is in, a waiting Host always notifies; a finished task notifies only while this app is not frontmost. Clicking one brings the window forward."
        case .settingsChannelHealthy: "Notification channel: connected to the Host API"
        case .settingsChannelUnauthorized: "Notification channel: waiting for the Host's credential — open the page once and it recovers on its own"
        case .settingsChannelReconnecting: "Notification channel: reconnecting…"
        case .settingsPageRefresh: "Auto-refresh page"
        case .settingsPageRefreshHelp: "Recarga la página por su cuenta cuando lleva un día abierta, para que una pantalla de larga duración no acumule memoria de renderizado. Ocurre solo cuando ninguna ventana está visible, y nunca mientras el Host espera tu respuesta."

        case .onboardingTitle: "Welcome to DSH Bezel"
        case .onboardingSubtitle: "Let's connect to your first dsh Host."
        case .onboardingSkip: "Skip — set up later"
        case .onboardingBack: "Back"
        case .onboardingDetecting: "Checking for a running dsh process…"
        case .onboardingRunningTitle: "A dsh process is running"
        case .onboardingRunningHelp: "Bind this app to it, or have this app start and manage a new one."
        case .onboardingNotRunningTitle: "No dsh process is running"
        case .onboardingNotRunningHelp: "This app can start and manage one for you."
        case .onboardingMatchedProcesses: "Matched processes:"
        case .onboardingChoiceBind: "Bind to the Running Process"
        case .onboardingChoiceBindHelp: "You already have a dsh serving its Web UI; this app just points at it."
        case .onboardingChoiceManaged: "Start a New Managed Process"
        case .onboardingChoiceManagedHelp: "This app starts the process, and terminates it when the app quits."
        case .onboardingBindLater: "Bind to a running process instead…"
        case .onboardingBindTitle: "Bind to the running process"
        case .onboardingBindHelp: "Both values come from that process's own startup output — the line `dsh web: http://…/?token=…` it printed where it was started. Paste them here."
        case .onboardingButtonBind: "Bind and Connect"
        case .onboardingManagedTitle: "Start a new managed dsh"
        case .onboardingManagedHelp: "A managed process is started by this app and terminated when the app quits or disconnects."
        case .onboardingManagedAuto: "Automatic"
        case .onboardingManagedAutoHelp: "Finds an installed dsh and starts it; installs it with npm first if it is missing."
        case .onboardingManagedManual: "Manual"
        case .onboardingManagedManualHelp: "You provide the start command; this app runs it and terminates it on quit."
        case .onboardingContinue: "Continue"
        case .onboardingAutoTitle: "Automatic managed start"
        case .onboardingAutoFound: "Found dsh: {1}"
        case .onboardingAutoNotFound: "No usable dsh is installed."
        case .onboardingInstallHelp: "dsh can be installed automatically with npm."
        case .onboardingInstallWillRun: "Will run: {1}"
        case .onboardingButtonInstall: "Install and Start"
        case .onboardingInstalling: "Installing (this can take a few minutes)…"
        case .onboardingInstallFailed: "Installation failed (exit status {1}). The output below may say why."
        case .onboardingInstallNoNPM: "npm was not found either, so dsh cannot be installed automatically. Install Node.js first, or use manual mode."
        case .onboardingButtonStart: "Start"
        case .onboardingStartFailed: "The managed process failed to start."
        case .onboardingRetry: "Retry"
        case .onboardingSwitchManual: "Use manual mode instead"
        case .onboardingManualTitle: "Manual managed start"
        case .onboardingManualCommand: "Start command"
        case .launchCommandHelp: "The command must print a `dsh web: http://…` startup line, like `dsh --profile web --port 0 --no-open`. It runs through your login shell; this app terminates it on quit."
        case .onboardingBindHostName: "Running dsh"
        case .settingsFieldLaunchCommand: "Custom start command (optional)"
        case .settingsFieldLaunchCommandPrompt: "leave empty for the standard invocation"
        case .tabNewTab: "New Tab"
        case .tabClose: "Close Tab"
        }
    }

    var simplifiedChinese: String {
        switch self {
        case .seedHostName: "本地 dsh"
        case .newHostName: "新 Host"
        case .untitledHost: "未命名 Host"
        case .invalidAddress: "无效的 Host 地址：{1}"

        case .statusNotConnected: "未连接"
        case .statusLoading: "加载中…"
        case .statusConnected: "已连接"
        case .phaseLocating: "正在查找可用的 dsh…"
        case .phaseStarting: "正在启动本地 dsh…"
        case .phaseCheckingPort: "正在检查端口是否已有 dsh 在运行…"

        case .failureNoDSH: "找不到可用的 dsh（已尝试 {1} 个位置，详见下方输出）"
        case .failureLaunchFailed: "无法启动 dsh：{1}"
        case .failureExited: "dsh 已退出（状态码 {1}）"
        case .failureExitedBeforeStart: "dsh 启动失败（状态码 {1}）"
        case .failureTimedOut: "dsh 在 {1} 秒内没有启动"

        case .originHostSetting: "Host 设置"
        case .originEnvironmentOverride: "BEZEL_DSH_PATH"
        case .originLoginShell: "登录 shell"
        case .originAppPath: "应用 PATH"
        case .originWellKnown: "常见安装位置"
        case .attemptSelected: "已选用"
        case .attemptNotExecutable: "不存在或没有执行权限"
        case .attemptDidNotRun: "存在，但 --version 无法成功运行（多半是找不到 node/npm）"
        case .attemptSkipped: "未尝试——查找的时间预算先用完了"
        case .diagnosticChosen: "dsh: {1}（来源：{2}）"
        case .diagnosticNoneFound: "找不到可用的 dsh：以下位置都试过了"
        case .diagnosticChildPATH: "子进程 PATH："

        case .toolbarSelectHost: "选择 Host"
        case .toolbarReload: "重新加载"
        case .toolbarOpenInBrowser: "在浏览器中打开"
        case .toolbarDisconnect: "断开"
        case .menuManageHosts: "管理 Host…"
        case .buttonConnectSelected: "连接选中的 Host"
        case .buttonStartDSH: "启动 dsh"
        case .buttonRestartDSH: "重启 dsh"
        case .buttonCheckHostSettings: "检查 Host 设置"
        case .connectPromptTitle: "选择要连接的 dsh Host"
        case .portConflictTitle: "端口已被运行中的 dsh 占用"
        case .portConflictMessage: "端口 {1} 上已有一个 dsh 在运行（{2}）。可以直接绑定到它，本应用不会再启动一个新的。"
        case .portConflictBind: "绑定到运行中的 dsh"
        case .portConflictCancel: "取消"

        case .menuFindTitle: "查找"
case .menuFind: "查找…"
        case .menuFindNext: "查找下一个"
        case .menuFindPrevious: "查找上一个"
        case .menuUseSelectionForFind: "用所选内容查找"
        case .findMatchesFound: "找到 {1} 处"

        case .settingsTabHosts: "Host"
        case .settingsTabGeneral: "通用"
        case .settingsLanguage: "语言"
        case .settingsLanguageHelp: "只影响本应用自己的界面。Host 的 Web UI 用哪种语言由 Host 自己决定，不随之改变。"
        case .settingsLanguageRestartNote: "菜单栏在下次启动时切换到新语言；其余界面立即生效。"
        case .settingsRestartNow: "立即重启"
        case .settingsSelectOrCreate: "选择或新建一个 Host"
        case .settingsNewHost: "新建 Host"
        case .settingsRemoveHost: "删除 Host"
        case .settingsFieldName: "名称"
        case .settingsFieldAddress: "地址"
        case .settingsFieldToken: "启动 token（可选）"
        case .settingsFieldTokenPrompt: "启动输出里的 ?token=…"
        case .settingsTokenHelp: "token 只用于首次换取 30 天有效的签名 Cookie。Cookie 失效或换了 Host 进程时，再粘贴一次 `dsh web` 启动输出里的完整地址即可。"
        case .settingsToggleManaged: "由本应用启动本地 dsh"
        case .settingsFieldExtraArguments: "额外参数"
        case .settingsFieldDSHPath: "dsh 可执行文件路径"
        case .settingsFieldDSHPathPrompt: "留空则自动查找"
        case .settingsManagedHelp: "以 `dsh --profile <profile> --port 0 --no-open` 启动：端口由系统分配，URL 从子进程输出解析。双击启动的 App 看不到终端里的 PATH，自动查找会依次询问登录 shell、用 `--version` 探测各候选；都不行时把 `command -v dsh` 的输出填在上面。"
        case .settingsButtonConnect: "连接到此 Host"
        case .settingsInvalidAddress: "地址无效"
        case .settingsConfigFile: "配置文件"
        case .settingsConfigHelp: "书签、选中的 Host 和语言都存在这个文件里。启动时读取，所以在应用关闭期间手改文件，下次打开即生效。"
        case .settingsWriteFailed: "无法写入配置文件：{1}"
        case .settingsUnreadableData: "配置文件无法解析，暂用默认 Host；文件本身未被覆盖。"
        case .settingsNewerFile: "这个配置文件由更新版本的应用写入（版本 {1}）。当前版本会按自己能理解的部分读取使用，但不会写回，因此这里的改动不会被保存。"

        case .errorCredentialRejected: "Host 拒绝了这个凭据：token 无效，且没有可用 Cookie"

        case .notificationAttentionApproval: "需要审批：有工具调用在等你决定"
        case .notificationAttentionQuestion: "Host 提了一个问题，在等你的回答"
        case .notificationAttentionPlan: "有计划在等你审阅"
        case .notificationTaskFinished: "任务已结束"
        case .settingsNotifications: "通知"
        case .settingsNotificationsHelp: "Host 等你处理时（工具审批、提问、计划审阅——任何会话都算），以及正在运行的任务结束时，发一条 macOS 通知。无论本应用处于什么状态，等待类通知都会发送；任务结束仅在本应用不在前台时发送。点击通知会把窗口带到前面。"
        case .settingsChannelHealthy: "通知通道：已连接 Host API"
        case .settingsChannelUnauthorized: "通知通道：等待 Host 凭证——打开一次页面后会自动恢复"
        case .settingsChannelReconnecting: "通知通道：正在重连…"
        case .settingsPageRefresh: "自动刷新页面"
        case .settingsPageRefreshHelp: "页面连续显示超过一天，或 WebKit 渲染进程内存超过上限时，自动重新加载页面，避免长时间使用积累内存垃圾。只在窗口不可见时执行，Host 等你答复时绝不刷新。"

        case .onboardingTitle: "欢迎使用 DSH Bezel"
        case .onboardingSubtitle: "先来连接你的第一个 dsh Host。"
        case .onboardingSkip: "跳过，稍后再设置"
        case .onboardingBack: "返回"
        case .onboardingDetecting: "正在检测是否有 DSH 进程在运行…"
        case .onboardingRunningTitle: "检测到有 DSH 进程正在运行"
        case .onboardingRunningHelp: "可以把本应用绑定到这个进程，也可以由本应用托管启动一个新进程。"
        case .onboardingNotRunningTitle: "未检测到正在运行的 DSH 进程"
        case .onboardingNotRunningHelp: "可以由本应用托管启动一个新的。"
        case .onboardingMatchedProcesses: "匹配到的进程："
        case .onboardingChoiceBind: "绑定当前进程"
        case .onboardingChoiceBindHelp: "你已经有一个 dsh 在提供 Web UI，本应用直接指向它。"
        case .onboardingChoiceManaged: "托管启动新进程"
        case .onboardingChoiceManagedHelp: "进程由本应用启动，退出本应用时随之终止。"
        case .onboardingBindLater: "改为绑定一个运行中的进程…"
        case .onboardingBindTitle: "绑定当前进程"
        case .onboardingBindHelp: "两项都来自该进程自己的启动输出——它启动时打印的 `dsh web: http://…/?token=…` 那一行。把它们粘贴到这里。"
        case .onboardingButtonBind: "绑定并连接"
        case .onboardingManagedTitle: "托管启动新的 dsh"
        case .onboardingManagedHelp: "托管进程由本应用启动；退出本应用或断开连接时会把它终止。"
        case .onboardingManagedAuto: "自动托管"
        case .onboardingManagedAutoHelp: "自动查找已安装的 dsh 并启动；如果没有安装，先通过 npm 自动安装。"
        case .onboardingManagedManual: "手动托管"
        case .onboardingManagedManualHelp: "由你提供启动命令，本应用负责执行，退出时终止该进程。"
        case .onboardingContinue: "继续"
        case .onboardingAutoTitle: "自动托管"
        case .onboardingAutoFound: "找到 dsh：{1}"
        case .onboardingAutoNotFound: "尚未安装可用的 dsh。"
        case .onboardingInstallHelp: "可以通过 npm 自动安装 dsh。"
        case .onboardingInstallWillRun: "将执行：{1}"
        case .onboardingButtonInstall: "安装并启动"
        case .onboardingInstalling: "正在安装（可能需要几分钟）…"
        case .onboardingInstallFailed: "安装失败（退出状态 {1}）。下方输出中可能有原因。"
        case .onboardingInstallNoNPM: "也没有找到 npm，无法自动安装 dsh。请先安装 Node.js，或改用手动托管。"
        case .onboardingButtonStart: "启动"
        case .onboardingStartFailed: "托管进程启动失败。"
        case .onboardingRetry: "重试"
        case .onboardingSwitchManual: "改用手动托管"
        case .onboardingManualTitle: "手动托管"
        case .onboardingManualCommand: "启动命令"
        case .launchCommandHelp: "命令需要输出 `dsh web: http://…` 这样的启动行，例如 `dsh --profile web --port 0 --no-open`。命令会通过登录 shell 执行；退出本应用时会终止该进程。"
        case .onboardingBindHostName: "运行中的 dsh"
        case .settingsFieldLaunchCommand: "自定义启动命令（可选）"
        case .settingsFieldLaunchCommandPrompt: "留空则使用标准启动命令"
        case .tabNewTab: "新建标签页"
        case .tabClose: "关闭标签页"
        }
    }

    /// Traditional Chinese wording for every message (Taiwan conventions).
    var traditionalChinese: String {
        switch self {
        case .seedHostName: "本機 dsh"
        case .newHostName: "新 Host"
        case .untitledHost: "未命名 Host"
        case .invalidAddress: "無效的 Host 位址：{1}"
        case .statusNotConnected: "未連線"
        case .statusLoading: "載入中…"
        case .statusConnected: "已連線"
        case .phaseLocating: "正在尋找可用的 dsh…"
        case .phaseStarting: "正在啟動本機 dsh…"
        case .phaseCheckingPort: "正在檢查連接埠是否已有 dsh 在執行…"
        case .failureNoDSH: "找不到可用的 dsh（已嘗試 {1} 個位置，詳見下方輸出）"
        case .failureLaunchFailed: "無法啟動 dsh：{1}"
        case .failureExited: "dsh 已結束（狀態碼 {1}）"
        case .failureExitedBeforeStart: "dsh 啟動失敗（狀態碼 {1}）"
        case .failureTimedOut: "dsh 在 {1} 秒內沒有啟動"
        case .originHostSetting: "Host 設定"
        case .originEnvironmentOverride: "BEZEL_DSH_PATH"
        case .originLoginShell: "登入 shell"
        case .originAppPath: "應用程式 PATH"
        case .originWellKnown: "常見安裝位置"
        case .attemptSelected: "已選用"
        case .attemptNotExecutable: "不存在或沒有執行權限"
        case .attemptDidNotRun: "存在，但 --version 無法成功執行（多半是找不到 node/npm）"
        case .attemptSkipped: "未嘗試——尋找的時間預算先用完了"
        case .diagnosticChosen: "dsh: {1}（來源：{2}）"
        case .diagnosticNoneFound: "找不到可用的 dsh：以下位置都試過了"
        case .diagnosticChildPATH: "子程序 PATH："
        case .toolbarSelectHost: "選擇 Host"
        case .toolbarReload: "重新整理"
        case .toolbarOpenInBrowser: "在瀏覽器中開啟"
        case .toolbarDisconnect: "中斷連線"
        case .menuManageHosts: "管理 Host…"
        case .buttonConnectSelected: "連線選中的 Host"
        case .buttonStartDSH: "啟動 dsh"
        case .buttonRestartDSH: "重新啟動 dsh"
        case .buttonCheckHostSettings: "檢查 Host 設定"
        case .connectPromptTitle: "選擇要連線的 dsh Host"
        case .portConflictTitle: "連接埠已被執行中的 dsh 佔用"
        case .portConflictMessage: "連接埠 {1} 上已有一個 dsh 在執行（{2}）。可以直接繫結到它，本應用不會再啟動一個。"
        case .portConflictBind: "繫結到執行中的 dsh"
        case .portConflictCancel: "取消"
        case .menuFindTitle: "尋找"
case .menuFind: "尋找…"
        case .menuFindNext: "尋找下一個"
        case .menuFindPrevious: "尋找上一個"
        case .menuUseSelectionForFind: "使用所選內容尋找"
        case .findMatchesFound: "找到 {1} 處"
        case .settingsTabHosts: "Host"
        case .settingsTabGeneral: "一般"
        case .settingsLanguage: "語言"
        case .settingsLanguageHelp: "只影響本應用程式自己的介面。Host 的 Web UI 用哪種語言由 Host 自己決定，不隨之改變。"
        case .settingsLanguageRestartNote: "選單列在下次啟動時切換到新語言；其餘介面立即生效。"
        case .settingsRestartNow: "立即重新啟動"
        case .settingsSelectOrCreate: "選擇或新增一個 Host"
        case .settingsNewHost: "新增 Host"
        case .settingsRemoveHost: "刪除 Host"
        case .settingsFieldName: "名稱"
        case .settingsFieldAddress: "位址"
        case .settingsFieldToken: "啟動 token（選填）"
        case .settingsFieldTokenPrompt: "啟動輸出裡的 ?token=…"
        case .settingsTokenHelp: "token 只用於首次換取 30 天有效的簽署 Cookie。Cookie 失效或換了 Host 程序時，再貼上一次 `dsh web` 啟動輸出裡的完整位址即可。"
        case .settingsToggleManaged: "由本應用程式啟動本機 dsh"
        case .settingsFieldExtraArguments: "額外參數"
        case .settingsFieldDSHPath: "dsh 可執行檔路徑"
        case .settingsFieldDSHPathPrompt: "留空則自動尋找"
        case .settingsManagedHelp: "以 `dsh --profile <profile> --port 0 --no-open` 啟動：連接埠由系統分配，URL 從子程序輸出解析。從 Finder 開啟的 App 看不到終端機裡的 PATH，自動尋找會依序詢問登入 shell、用 `--version` 探測各候選；都不行時把 `command -v dsh` 的輸出填在上面。"
        case .settingsButtonConnect: "連線到此 Host"
        case .settingsInvalidAddress: "位址無效"
        case .settingsConfigFile: "設定檔"
        case .settingsConfigHelp: "書籤、選中的 Host 和語言都存在這個檔案裡。啟動時讀取，所以在應用程式關閉期間手改檔案，下次開啟即生效。"
        case .settingsWriteFailed: "無法寫入設定檔：{1}"
        case .settingsUnreadableData: "設定檔無法解析，暫用預設 Host；檔案本身未被覆寫。"
        case .settingsNewerFile: "這個設定檔由較新版本的應用程式寫入（版本 {1}）。目前版本會按自己能理解的部分讀取使用，但不會寫回，因此這裡的改動不會被儲存。"
        case .errorCredentialRejected: "Host 拒絕了這個憑證：token 無效，且沒有可用 Cookie"
        case .notificationAttentionApproval: "需要核准：有工具呼叫在等你決定"
        case .notificationAttentionQuestion: "Host 提了一個問題，在等你的回答"
        case .notificationAttentionPlan: "有計畫在等你審閱"
        case .notificationTaskFinished: "任務已結束"
        case .settingsNotifications: "通知"
        case .settingsNotificationsHelp: "Host 等你處理時（工具核准、提問、計畫審閱——任何對話都算），以及正在執行的任務結束時，發一則 macOS 通知。無論本應用程式處於什麼狀態，等待類通知都會傳送；任務結束僅在本應用程式不在前景時傳送。點按通知會把視窗帶到前面。"
        case .settingsChannelHealthy: "通知頻道：已連線 Host API"
        case .settingsChannelUnauthorized: "通知頻道：等待 Host 憑證——開啟一次頁面後會自動恢復"
        case .settingsChannelReconnecting: "通知頻道：正在重新連線…"
        case .settingsPageRefresh: "自動重新整理頁面"
        case .settingsPageRefreshHelp: "頁面連續顯示超過一天，或 WebKit 渲染程序記憶體超過上限時，自動重新載入頁面，避免長時間使用累積記憶體垃圾。只在視窗不可見時執行，Host 等你答覆時絕不重新整理。"
        case .onboardingTitle: "歡迎使用 DSH Bezel"
        case .onboardingSubtitle: "先來連線你的第一個 dsh Host。"
        case .onboardingSkip: "略過，稍後再設定"
        case .onboardingBack: "返回"
        case .onboardingDetecting: "正在偵測是否有 DSH 程序在執行…"
        case .onboardingRunningTitle: "偵測到有 DSH 程序正在執行"
        case .onboardingRunningHelp: "可以把本應用程式綁定到這個程序，也可以由本應用程式代管啟動一個新程序。"
        case .onboardingNotRunningTitle: "未偵測到正在執行的 DSH 程序"
        case .onboardingNotRunningHelp: "可以由本應用程式代管啟動一個新的。"
        case .onboardingMatchedProcesses: "相符的程序："
        case .onboardingChoiceBind: "綁定目前程序"
        case .onboardingChoiceBindHelp: "你已經有一個 dsh 在提供 Web UI，本應用程式直接指向它。"
        case .onboardingChoiceManaged: "代管啟動新程序"
        case .onboardingChoiceManagedHelp: "程序由本應用程式啟動，結束本應用程式時隨之終止。"
        case .onboardingBindLater: "改為綁定一個執行中的程序…"
        case .onboardingBindTitle: "綁定目前程序"
        case .onboardingBindHelp: "兩項都來自該程序自己的啟動輸出——它啟動時列印的 `dsh web: http://…/?token=…` 那一行。把它們貼到這裡。"
        case .onboardingButtonBind: "綁定並連線"
        case .onboardingManagedTitle: "代管啟動新的 dsh"
        case .onboardingManagedHelp: "代管程序由本應用程式啟動；結束本應用程式或中斷連線時會把它終止。"
        case .onboardingManagedAuto: "自動代管"
        case .onboardingManagedAutoHelp: "自動尋找已安裝的 dsh 並啟動；如果沒有安裝，先透過 npm 自動安裝。"
        case .onboardingManagedManual: "手動代管"
        case .onboardingManagedManualHelp: "由你提供啟動命令，本應用程式負責執行，結束時終止該程序。"
        case .onboardingContinue: "繼續"
        case .onboardingAutoTitle: "自動代管"
        case .onboardingAutoFound: "找到 dsh：{1}"
        case .onboardingAutoNotFound: "尚未安裝可用的 dsh。"
        case .onboardingInstallHelp: "可以透過 npm 自動安裝 dsh。"
        case .onboardingInstallWillRun: "將執行：{1}"
        case .onboardingButtonInstall: "安裝並啟動"
        case .onboardingInstalling: "正在安裝（可能需要幾分鐘）…"
        case .onboardingInstallFailed: "安裝失敗（結束狀態 {1}）。下方輸出中可能有原因。"
        case .onboardingInstallNoNPM: "也沒有找到 npm，無法自動安裝 dsh。請先安裝 Node.js，或改用手動代管。"
        case .onboardingButtonStart: "啟動"
        case .onboardingStartFailed: "代管程序啟動失敗。"
        case .onboardingRetry: "重試"
        case .onboardingSwitchManual: "改用手動代管"
        case .onboardingManualTitle: "手動代管"
        case .onboardingManualCommand: "啟動命令"
        case .launchCommandHelp: "命令需要輸出 `dsh web: http://…` 這樣的啟動行，例如 `dsh --profile web --port 0 --no-open`。命令會透過登入 shell 執行；結束本應用程式時會終止該程序。"
        case .onboardingBindHostName: "執行中的 dsh"
        case .settingsFieldLaunchCommand: "自訂啟動命令（選填）"
        case .settingsFieldLaunchCommandPrompt: "留空則使用標準啟動命令"
        case .tabNewTab: "新增分頁"
        case .tabClose: "關閉分頁"
        }
    }

    /// Japanese wording for every message.
    var japanese: String {
        switch self {
        case .seedHostName: "ローカル dsh"
        case .newHostName: "新しい Host"
        case .untitledHost: "名称未設定の Host"
        case .invalidAddress: "Host のアドレスが無効です：{1}"
        case .statusNotConnected: "未接続"
        case .statusLoading: "読み込み中…"
        case .statusConnected: "接続済み"
        case .phaseLocating: "使用可能な dsh を探しています…"
        case .phaseStarting: "ローカルの dsh を起動しています…"
        case .phaseCheckingPort: "ポートを既に dsh が使用していないか確認中…"
        case .failureNoDSH: "使用可能な dsh が見つかりません（{1} か所を試しました。詳細は下の出力を参照）"
        case .failureLaunchFailed: "dsh を起動できません：{1}"
        case .failureExited: "dsh が終了しました（ステータス {1}）"
        case .failureExitedBeforeStart: "dsh の起動に失敗しました（ステータス {1}）"
        case .failureTimedOut: "dsh が {1} 秒以内に起動しませんでした"
        case .originHostSetting: "Host 設定"
        case .originEnvironmentOverride: "BEZEL_DSH_PATH"
        case .originLoginShell: "ログインシェル"
        case .originAppPath: "アプリの PATH"
        case .originWellKnown: "一般的なインストール先"
        case .attemptSelected: "選択"
        case .attemptNotExecutable: "存在しない、または実行権限がありません"
        case .attemptDidNotRun: "存在しますが `--version` を実行できません（多くの場合 PATH に node か npm がありません）"
        case .attemptSkipped: "未試行——探索の時間制限に達しました"
        case .diagnosticChosen: "dsh: {1}（ソース：{2}）"
        case .diagnosticNoneFound: "使用可能な dsh が見つかりません。以下のすべての場所を試しました"
        case .diagnosticChildPATH: "子プロセスの PATH："
        case .toolbarSelectHost: "Host を選択"
        case .toolbarReload: "再読み込み"
        case .toolbarOpenInBrowser: "ブラウザで開く"
        case .toolbarDisconnect: "切断"
        case .menuManageHosts: "Host を管理…"
        case .buttonConnectSelected: "選択した Host に接続"
        case .buttonStartDSH: "dsh を起動"
        case .buttonRestartDSH: "dsh を再起動"
        case .buttonCheckHostSettings: "Host の設定を確認"
        case .connectPromptTitle: "接続する dsh Host を選択してください"
        case .portConflictTitle: "ポートは実行中の dsh が使用中です"
        case .portConflictMessage: "ポート {1} では既に dsh が実行中です（{2}）。その dsh にバインドできます。このアプリは新しい dsh を起動しません。"
        case .portConflictBind: "実行中の dsh にバインド"
        case .portConflictCancel: "キャンセル"
        case .menuFindTitle: "検索"
case .menuFind: "検索…"
        case .menuFindNext: "次を検索"
        case .menuFindPrevious: "前を検索"
        case .menuUseSelectionForFind: "選択範囲を検索に使用"
        case .findMatchesFound: "{1} 件見つかりました"
        case .settingsTabHosts: "Host"
        case .settingsTabGeneral: "全般"
        case .settingsLanguage: "言語"
        case .settingsLanguageHelp: "このアプリ自身のインターフェイスにのみ適用されます。Host の Web UI の言語は Host 側の設定であり、変更されません。"
        case .settingsLanguageRestartNote: "メニューバーは次回起動時に新しい言語になります。それ以外はすぐに切り替わります。"
        case .settingsRestartNow: "今すぐ再起動"
        case .settingsSelectOrCreate: "Host を選択または作成してください"
        case .settingsNewHost: "新しい Host"
        case .settingsRemoveHost: "Host を削除"
        case .settingsFieldName: "名称"
        case .settingsFieldAddress: "アドレス"
        case .settingsFieldToken: "起動トークン（省略可）"
        case .settingsFieldTokenPrompt: "起動時の出力にある ?token=…"
        case .settingsTokenHelp: "トークンは 30 日間有効な署名付き Cookie を発行する最初の 1 回だけ使われます。Cookie の期限が切れた場合や Host プロセスを入れ替えた場合は、`dsh web` の出力にある完全なアドレスをもう一度貼り付けてください。"
        case .settingsToggleManaged: "この Host 用にローカルの dsh を起動する"
        case .settingsFieldExtraArguments: "追加の引数"
        case .settingsFieldDSHPath: "dsh 実行ファイルのパス"
        case .settingsFieldDSHPathPrompt: "空欄にすると自動で探します"
        case .settingsManagedHelp: "`dsh --profile <profile> --port 0 --no-open` を実行します：ポートはシステムが選び、URL は子プロセスの出力から読み取ります。Finder から起動したアプリはターミナルの PATH を見られないため、探索はログインシェルに尋ね、各候補を `--version` で確認します。どれも動かない場合は `command -v dsh` の出力を上の欄に入力してください。"
        case .settingsButtonConnect: "この Host に接続"
        case .settingsInvalidAddress: "アドレスが無効です"
        case .settingsConfigFile: "設定ファイル"
        case .settingsConfigHelp: "ブックマーク、選択中の Host、言語はすべてこのファイルにあります。起動時に読み込まれるため、アプリを閉じている間の編集は次回起動時に反映されます。"
        case .settingsWriteFailed: "設定ファイルを書き込めません：{1}"
        case .settingsUnreadableData: "設定ファイルを読み取れないため、既定の Host を使用しています。ファイル自体は上書きされていません。"
        case .settingsNewerFile: "この設定ファイルは新しいバージョンのアプリ（バージョン {1}）で書かれています。このバージョンが理解できる範囲で使用しますが、書き戻しは行わないため、ここでの変更は保存されません。"
        case .errorCredentialRejected: "Host がこの資格情報を拒否しました：トークンが無効で、使用可能な Cookie もありません"
        case .notificationAttentionApproval: "承認が必要です：ツール呼び出しがあなたの判断を待っています"
        case .notificationAttentionQuestion: "Host が質問し、回答を待っています"
        case .notificationAttentionPlan: "計画がレビューを待っています"
        case .notificationTaskFinished: "タスクが完了しました"
        case .settingsNotifications: "通知"
        case .settingsNotificationsHelp: "Host が待っているとき（ツールの承認、質問、計画のレビュー——どのセッションでも）と、実行中のタスクが終わったときに macOS の通知を送ります。アプリの状態にかかわらず、待ち状態は常に通知され、タスクの終了はこのアプリが最前面にないときだけ通知されます。通知をクリックするとウインドウが前面に出ます。"
        case .settingsChannelHealthy: "通知チャネル：Host API に接続済み"
        case .settingsChannelUnauthorized: "通知チャネル：Host の資格情報を待っています——ページを一度開けば自動的に回復します"
        case .settingsChannelReconnecting: "通知チャネル：再接続中…"
        case .settingsPageRefresh: "ページの自動再読み込み"
        case .settingsPageRefreshHelp: "ページの表示が1日を超えたとき、または WebKit コンテンツプロセスのメモリが上限を超えたときに、ページを自動で再読み込みし、長時間の使用でメモリが溜まるのを防ぎます。ウィンドウが見えていないときだけ実行され、Host があなたの回答を待っている間は決して実行されません。"
        case .onboardingTitle: "DSH Bezel へようこそ"
        case .onboardingSubtitle: "まずは最初の dsh Host に接続しましょう。"
        case .onboardingSkip: "スキップ——後で設定する"
        case .onboardingBack: "戻る"
        case .onboardingDetecting: "実行中の dsh プロセスを確認しています…"
        case .onboardingRunningTitle: "dsh プロセスが実行中です"
        case .onboardingRunningHelp: "このアプリをそれに接続するか、新しいプロセスをこのアプリに管理させることができます。"
        case .onboardingNotRunningTitle: "実行中の dsh プロセスはありません"
        case .onboardingNotRunningHelp: "このアプリが代わりに起動して管理できます。"
        case .onboardingMatchedProcesses: "一致したプロセス："
        case .onboardingChoiceBind: "実行中のプロセスに接続"
        case .onboardingChoiceBindHelp: "すでに Web UI を提供している dsh があり、このアプリはそこを指すだけです。"
        case .onboardingChoiceManaged: "管理された新しいプロセスを起動"
        case .onboardingChoiceManagedHelp: "プロセスはこのアプリが起動し、アプリの終了時に終了させます。"
        case .onboardingBindLater: "代わりに実行中のプロセスへ接続する…"
        case .onboardingBindTitle: "実行中のプロセスに接続"
        case .onboardingBindHelp: "どちらの値もそのプロセス自身の起動出力——起動した場所に表示された `dsh web: http://…/?token=…` の行——から得られます。ここに貼り付けてください。"
        case .onboardingButtonBind: "バインドして接続"
        case .onboardingManagedTitle: "管理された新しい dsh を起動"
        case .onboardingManagedHelp: "管理されたプロセスはこのアプリが起動し、アプリの終了時または切断時に終了します。"
        case .onboardingManagedAuto: "自動"
        case .onboardingManagedAutoHelp: "インストール済みの dsh を見つけて起動します。見つからない場合は npm で先にインストールします。"
        case .onboardingManagedManual: "手動"
        case .onboardingManagedManualHelp: "起動コマンドはあなたが指定し、このアプリが実行して終了時に終了させます。"
        case .onboardingContinue: "続ける"
        case .onboardingAutoTitle: "自動での管理起動"
        case .onboardingAutoFound: "dsh が見つかりました：{1}"
        case .onboardingAutoNotFound: "使用可能な dsh がインストールされていません。"
        case .onboardingInstallHelp: "dsh は npm で自動的にインストールできます。"
        case .onboardingInstallWillRun: "実行内容：{1}"
        case .onboardingButtonInstall: "インストールして起動"
        case .onboardingInstalling: "インストール中（数分かかることがあります）…"
        case .onboardingInstallFailed: "インストールに失敗しました（終了ステータス {1}）。下の出力に原因があるかもしれません。"
        case .onboardingInstallNoNPM: "npm も見つからないため、dsh を自動でインストールできません。まず Node.js をインストールするか、手動モードを使ってください。"
        case .onboardingButtonStart: "起動"
        case .onboardingStartFailed: "管理されたプロセスの起動に失敗しました。"
        case .onboardingRetry: "再試行"
        case .onboardingSwitchManual: "代わりに手動モードを使う"
        case .onboardingManualTitle: "手動での管理起動"
        case .onboardingManualCommand: "起動コマンド"
        case .launchCommandHelp: "コマンドは `dsh --profile web --port 0 --no-open` のように `dsh web: http://…` という起動行を出力する必要があります。ログインシェル経由で実行され、アプリの終了時に終了します。"
        case .onboardingBindHostName: "実行中の dsh"
        case .settingsFieldLaunchCommand: "カスタム起動コマンド（省略可）"
        case .settingsFieldLaunchCommandPrompt: "空欄にすると標準の起動方法を使います"
        case .tabNewTab: "新しいタブ"
        case .tabClose: "タブを閉じる"
        }
    }

    /// French wording for every message.
    var french: String {
        switch self {
        case .seedHostName: "dsh local"
        case .newHostName: "Nouvel Host"
        case .untitledHost: "Host sans titre"
        case .invalidAddress: "Adresse d'Host invalide : {1}"
        case .statusNotConnected: "Non connecté"
        case .statusLoading: "Chargement…"
        case .statusConnected: "Connecté"
        case .phaseLocating: "Recherche d'un dsh utilisable…"
        case .phaseStarting: "Démarrage du dsh local…"
        case .phaseCheckingPort: "Vérification : un dsh sert-il déjà ce port…"
        case .failureNoDSH: "Aucun dsh utilisable trouvé ({1} emplacements essayés ; voir la sortie ci-dessous)"
        case .failureLaunchFailed: "Impossible de lancer dsh : {1}"
        case .failureExited: "dsh s'est arrêté (statut {1})"
        case .failureExitedBeforeStart: "dsh n'a pas pu démarrer (statut {1})"
        case .failureTimedOut: "dsh n'a pas démarré en {1} secondes"
        case .originHostSetting: "Réglage de l'Host"
        case .originEnvironmentOverride: "BEZEL_DSH_PATH"
        case .originLoginShell: "shell de connexion"
        case .originAppPath: "PATH de l'app"
        case .originWellKnown: "emplacements d'installation courants"
        case .attemptSelected: "retenu"
        case .attemptNotExecutable: "absent ou non exécutable"
        case .attemptDidNotRun: "présent, mais `--version` ne peut pas s'exécuter (souvent node ou npm absent du PATH)"
        case .attemptSkipped: "non essayé — le temps imparti à la recherche s'est épuisé avant"
        case .diagnosticChosen: "dsh : {1} (source : {2})"
        case .diagnosticNoneFound: "Aucun dsh utilisable trouvé ; tous les emplacements ci-dessous ont été essayés"
        case .diagnosticChildPATH: "PATH du processus enfant :"
        case .toolbarSelectHost: "Sélectionner un Host"
        case .toolbarReload: "Recharger"
        case .toolbarOpenInBrowser: "Ouvrir dans le navigateur"
        case .toolbarDisconnect: "Se déconnecter"
        case .menuManageHosts: "Gérer les Hosts…"
        case .buttonConnectSelected: "Connecter l'Host sélectionné"
        case .buttonStartDSH: "Démarrer dsh"
        case .buttonRestartDSH: "Redémarrer dsh"
        case .buttonCheckHostSettings: "Vérifier les réglages de l'Host"
        case .connectPromptTitle: "Choisissez un Host dsh auquel vous connecter"
        case .portConflictTitle: "Port déjà occupé par un dsh en cours"
        case .portConflictMessage: "Un dsh tourne déjà sur le port {1} ({2}). Vous pouvez vous y lier directement ; cette application n'en démarrera pas un autre."
        case .portConflictBind: "Se lier au dsh en cours"
        case .portConflictCancel: "Annuler"
        case .menuFindTitle: "Rechercher"
case .menuFind: "Rechercher…"
        case .menuFindNext: "Suivant"
        case .menuFindPrevious: "Précédent"
        case .menuUseSelectionForFind: "Utiliser la sélection pour rechercher"
        case .findMatchesFound: "{1} résultats"
        case .settingsTabHosts: "Hosts"
        case .settingsTabGeneral: "Général"
        case .settingsLanguage: "Langue"
        case .settingsLanguageHelp: "S'applique uniquement à l'interface de cette app. Cela ne change pas la langue de l'interface web de l'Host, qui est un réglage propre à l'Host."
        case .settingsLanguageRestartNote: "La barre de menus prend la nouvelle langue au prochain lancement ; tout le reste change immédiatement."
        case .settingsRestartNow: "Redémarrer maintenant"
        case .settingsSelectOrCreate: "Sélectionnez ou créez un Host"
        case .settingsNewHost: "Nouvel Host"
        case .settingsRemoveHost: "Supprimer l'Host"
        case .settingsFieldName: "Nom"
        case .settingsFieldAddress: "Adresse"
        case .settingsFieldToken: "Token de démarrage (facultatif)"
        case .settingsFieldTokenPrompt: "le ?token=… de la sortie de démarrage"
        case .settingsTokenHelp: "Le token ne sert qu'une fois, pour obtenir le cookie signé valable 30 jours. Si le cookie expire ou si le processus Host est remplacé, collez à nouveau l'adresse complète affichée par `dsh web`."
        case .settingsToggleManaged: "Démarrer un dsh local pour cet Host"
        case .settingsFieldExtraArguments: "Arguments supplémentaires"
        case .settingsFieldDSHPath: "Chemin de l'exécutable dsh"
        case .settingsFieldDSHPathPrompt: "laisser vide pour une recherche automatique"
        case .settingsManagedHelp: "Exécute `dsh --profile <profile> --port 0 --no-open` : le système choisit le port et l'URL est lue dans la sortie du processus enfant. Une app lancée depuis le Finder ne voit pas le PATH de votre terminal ; la recherche interroge donc le shell de connexion et teste chaque candidat avec `--version`. Si aucun ne fonctionne, indiquez ci-dessus la sortie de `command -v dsh`."
        case .settingsButtonConnect: "Se connecter à cet Host"
        case .settingsInvalidAddress: "Adresse invalide"
        case .settingsConfigFile: "Fichier de configuration"
        case .settingsConfigHelp: "Les signets, l'Host sélectionné et la langue vivent tous dans ce fichier. Il est lu au lancement : les modifications faites app fermée prennent effet à l'ouverture suivante."
        case .settingsWriteFailed: "Impossible d'écrire le fichier de configuration : {1}"
        case .settingsUnreadableData: "Le fichier de configuration ne peut pas être décodé ; l'Host par défaut est utilisé. Le fichier lui-même n'a pas été écrasé."
        case .settingsNewerFile: "Ce fichier de configuration a été écrit par une version plus récente de l'app (version {1}). Il est utilisé dans la mesure où cette version le comprend, mais rien n'est réécrit : les modifications faites ici ne seront pas conservées."
        case .errorCredentialRejected: "L'Host a rejeté ces identifiants : le token est invalide et aucun cookie utilisable n'est présent"
        case .notificationAttentionApproval: "Approbation requise : un appel d'outil attend votre décision"
        case .notificationAttentionQuestion: "L'Host a posé une question et attend votre réponse"
        case .notificationAttentionPlan: "Un plan attend votre relecture"
        case .notificationTaskFinished: "La tâche est terminée"
        case .settingsNotifications: "Notifications"
        case .settingsNotificationsHelp: "Une notification macOS quand l'Host vous attend — approbation d'outil, question, relecture de plan, dans n'importe quelle session — et quand une tâche en cours se termine. Quel que soit l'état de cette app, une attente est toujours notifiée ; la fin d'une tâche seulement quand cette app n'est pas au premier plan ; un clic ramène la fenêtre devant."
        case .settingsChannelHealthy: "Canal de notification : connecté à l'API de l'Host"
        case .settingsChannelUnauthorized: "Canal de notification : en attente de l'identifiant de l'Host — ouvrez la page une fois, il se rétablira tout seul"
        case .settingsChannelReconnecting: "Canal de notification : reconnexion…"
        case .settingsPageRefresh: "Renouvellement automatique de la page"
        case .settingsPageRefreshHelp: "Recharge la page de sa propre initiative quand elle est affichée depuis plus d'un jour, ou quand le processus de contenu WebKit dépasse une limite de mémoire, pour éviter qu'un affichage de longue durée n'accumule de la mémoire de rendu. N'arrive que lorsqu'aucune fenêtre n'est visible, et jamais pendant que le Host attend votre réponse."
        case .onboardingTitle: "Bienvenue dans DSH Bezel"
        case .onboardingSubtitle: "Connectons-nous à votre premier Host dsh."
        case .onboardingSkip: "Ignorer — configurer plus tard"
        case .onboardingBack: "Retour"
        case .onboardingDetecting: "Recherche d'un processus dsh en cours d'exécution…"
        case .onboardingRunningTitle: "Un processus dsh est en cours d'exécution"
        case .onboardingRunningHelp: "Reliez cette app à ce processus, ou laissez-la en démarrer et gérer un nouveau."
        case .onboardingNotRunningTitle: "Aucun processus dsh n'est en cours d'exécution"
        case .onboardingNotRunningHelp: "Cette app peut en démarrer et en gérer un pour vous."
        case .onboardingMatchedProcesses: "Processus correspondants :"
        case .onboardingChoiceBind: "Se relier au processus en cours"
        case .onboardingChoiceBindHelp: "Vous avez déjà un dsh qui sert son interface web ; cette app pointe simplement dessus."
        case .onboardingChoiceManaged: "Démarrer un nouveau processus géré"
        case .onboardingChoiceManagedHelp: "Le processus est démarré par cette app, et arrêté quand l'app quitte."
        case .onboardingBindLater: "Se relier plutôt à un processus en cours…"
        case .onboardingBindTitle: "Se relier au processus en cours"
        case .onboardingBindHelp: "Les deux valeurs viennent de la sortie de démarrage de ce processus — la ligne `dsh web: http://…/?token=…` affichée là où il a été lancé. Collez-les ici."
        case .onboardingButtonBind: "Relier et connecter"
        case .onboardingManagedTitle: "Démarrer un nouveau dsh géré"
        case .onboardingManagedHelp: "Un processus géré est démarré par cette app et arrêté quand l'app quitte ou se déconnecte."
        case .onboardingManagedAuto: "Automatique"
        case .onboardingManagedAutoHelp: "Trouve un dsh installé et le démarre ; l'installe d'abord avec npm s'il est absent."
        case .onboardingManagedManual: "Manuel"
        case .onboardingManagedManualHelp: "Vous fournissez la commande de démarrage ; cette app l'exécute et l'arrête en quittant."
        case .onboardingContinue: "Continuer"
        case .onboardingAutoTitle: "Démarrage géré automatique"
        case .onboardingAutoFound: "dsh trouvé : {1}"
        case .onboardingAutoNotFound: "Aucun dsh utilisable n'est installé."
        case .onboardingInstallHelp: "dsh peut être installé automatiquement avec npm."
        case .onboardingInstallWillRun: "Sera exécuté : {1}"
        case .onboardingButtonInstall: "Installer et démarrer"
        case .onboardingInstalling: "Installation (cela peut prendre quelques minutes)…"
        case .onboardingInstallFailed: "L'installation a échoué (statut de sortie {1}). La sortie ci-dessous peut en dire la raison."
        case .onboardingInstallNoNPM: "npm n'a pas été trouvé non plus : dsh ne peut pas être installé automatiquement. Installez d'abord Node.js, ou utilisez le mode manuel."
        case .onboardingButtonStart: "Démarrer"
        case .onboardingStartFailed: "Le processus géré n'a pas pu démarrer."
        case .onboardingRetry: "Réessayer"
        case .onboardingSwitchManual: "Utiliser plutôt le mode manuel"
        case .onboardingManualTitle: "Démarrage géré manuel"
        case .onboardingManualCommand: "Commande de démarrage"
        case .launchCommandHelp: "La commande doit afficher une ligne de démarrage `dsh web: http://…`, comme `dsh --profile web --port 0 --no-open`. Elle passe par votre shell de connexion ; cette app l'arrête en quittant."
        case .onboardingBindHostName: "dsh en cours d'exécution"
        case .settingsFieldLaunchCommand: "Commande de démarrage personnalisée (facultatif)"
        case .settingsFieldLaunchCommandPrompt: "laisser vide pour l'invocation standard"
        case .tabNewTab: "Nouvel onglet"
        case .tabClose: "Fermer l'onglet"
        }
    }

    /// German wording for every message.
    var german: String {
        switch self {
        case .seedHostName: "Lokales dsh"
        case .newHostName: "Neuer Host"
        case .untitledHost: "Unbenannter Host"
        case .invalidAddress: "Ungültige Host-Adresse: {1}"
        case .statusNotConnected: "Nicht verbunden"
        case .statusLoading: "Wird geladen…"
        case .statusConnected: "Verbunden"
        case .phaseLocating: "Es wird nach einem nutzbaren dsh gesucht…"
        case .phaseStarting: "Lokales dsh wird gestartet…"
        case .phaseCheckingPort: "Prüfen, ob bereits ein dsh diesen Port belegt…"
        case .failureNoDSH: "Kein nutzbares dsh gefunden ({1} Orte versucht; siehe Ausgabe unten)"
        case .failureLaunchFailed: "dsh konnte nicht gestartet werden: {1}"
        case .failureExited: "dsh wurde beendet (Status {1})"
        case .failureExitedBeforeStart: "dsh konnte nicht starten (Status {1})"
        case .failureTimedOut: "dsh ist nicht innerhalb von {1} Sekunden gestartet"
        case .originHostSetting: "Host-Einstellung"
        case .originEnvironmentOverride: "BEZEL_DSH_PATH"
        case .originLoginShell: "Anmelde-Shell"
        case .originAppPath: "App-PATH"
        case .originWellKnown: "übliche Installationsorte"
        case .attemptSelected: "ausgewählt"
        case .attemptNotExecutable: "nicht vorhanden oder nicht ausführbar"
        case .attemptDidNotRun: "vorhanden, aber `--version` lässt sich nicht ausführen (meist fehlt node oder npm im PATH)"
        case .attemptSkipped: "nicht versucht — das Zeitbudget der Suche war vorher aufgebraucht"
        case .diagnosticChosen: "dsh: {1} (Quelle: {2})"
        case .diagnosticNoneFound: "Kein nutzbares dsh gefunden; jeder Ort unten wurde versucht"
        case .diagnosticChildPATH: "PATH des Kindprozesses:"
        case .toolbarSelectHost: "Host auswählen"
        case .toolbarReload: "Neu laden"
        case .toolbarOpenInBrowser: "Im Browser öffnen"
        case .toolbarDisconnect: "Trennen"
        case .menuManageHosts: "Hosts verwalten…"
        case .buttonConnectSelected: "Ausgewählten Host verbinden"
        case .buttonStartDSH: "dsh starten"
        case .buttonRestartDSH: "dsh neu starten"
        case .buttonCheckHostSettings: "Host-Einstellungen prüfen"
        case .connectPromptTitle: "Wählen Sie einen dsh-Host zum Verbinden"
        case .portConflictTitle: "Port wird bereits von einem laufenden dsh belegt"
        case .portConflictMessage: "Auf Port {1} läuft bereits ein dsh ({2}). Sie können dich direkt damit verbinden; diese App startet keinen weiteren."
        case .portConflictBind: "An laufenden dsh binden"
        case .portConflictCancel: "Abbrechen"
        case .menuFindTitle: "Suchen"
case .menuFind: "Suchen…"
        case .menuFindNext: "Weiter"
        case .menuFindPrevious: "Zurück"
        case .menuUseSelectionForFind: "Auswahl zum Suchen verwenden"
        case .findMatchesFound: "{1} gefunden"
        case .settingsTabHosts: "Hosts"
        case .settingsTabGeneral: "Allgemein"
        case .settingsLanguage: "Sprache"
        case .settingsLanguageHelp: "Gilt nur für die Oberfläche dieser App. Die Sprache der Web-UI des Hosts bleibt unberührt, das ist eine Einstellung des Hosts selbst."
        case .settingsLanguageRestartNote: "Die Menüleiste übernimmt die neue Sprache beim nächsten Start; alles andere wechselt sofort."
        case .settingsRestartNow: "Jetzt neu starten"
        case .settingsSelectOrCreate: "Host auswählen oder anlegen"
        case .settingsNewHost: "Neuer Host"
        case .settingsRemoveHost: "Host entfernen"
        case .settingsFieldName: "Name"
        case .settingsFieldAddress: "Adresse"
        case .settingsFieldToken: "Start-Token (optional)"
        case .settingsFieldTokenPrompt: "das ?token=… aus der Startausgabe"
        case .settingsTokenHelp: "Das Token wird nur einmal verwendet, um das 30 Tage gültige signierte Cookie zu erhalten. Läuft das Cookie ab oder wird der Host-Prozess ersetzt, fügen Sie die vollständige Adresse aus der Ausgabe von `dsh web` erneut ein."
        case .settingsToggleManaged: "Für diesen Host ein lokales dsh starten"
        case .settingsFieldExtraArguments: "Zusätzliche Argumente"
        case .settingsFieldDSHPath: "Pfad zur dsh-Programmdatei"
        case .settingsFieldDSHPathPrompt: "leer lassen, um automatisch zu suchen"
        case .settingsManagedHelp: "Führt `dsh --profile <profile> --port 0 --no-open` aus: das System wählt den Port, die URL wird aus der Ausgabe des Kindprozesses gelesen. Eine aus dem Finder gestartete App sieht den PATH Ihres Terminals nicht, deshalb fragt die Suche die Login-Shell und prüft jeden Kandidaten mit `--version`. Funktioniert keiner, tragen Sie oben die Ausgabe von `command -v dsh` ein."
        case .settingsButtonConnect: "Mit diesem Host verbinden"
        case .settingsInvalidAddress: "Ungültige Adresse"
        case .settingsConfigFile: "Konfigurationsdatei"
        case .settingsConfigHelp: "Lesezeichen, der ausgewählte Host und die Sprache stehen alle in dieser Datei. Sie wird beim Start gelesen, Änderungen bei geschlossener App wirken also beim nächsten Öffnen."
        case .settingsWriteFailed: "Die Konfigurationsdatei konnte nicht geschrieben werden: {1}"
        case .settingsUnreadableData: "Die Konfigurationsdatei kann nicht gelesen werden, daher wird der Standard-Host verwendet. Die Datei selbst wurde nicht überschrieben."
        case .settingsNewerFile: "Diese Konfigurationsdatei wurde von einer neueren Version der App geschrieben (Version {1}). Sie wird soweit genutzt, wie diese Version sie versteht, aber nichts wird zurückgeschrieben — Änderungen hier bleiben nicht erhalten."
        case .errorCredentialRejected: "Der Host hat diese Anmeldedaten abgelehnt: das Token ist ungültig und es liegt kein nutzbares Cookie vor"
        case .notificationAttentionApproval: "Freigabe nötig: ein Werkzeugaufruf wartet auf Ihre Entscheidung"
        case .notificationAttentionQuestion: "Der Host hat eine Frage gestellt und wartet auf Ihre Antwort"
        case .notificationAttentionPlan: "Ein Plan wartet auf Ihre Durchsicht"
        case .notificationTaskFinished: "Die Aufgabe ist abgeschlossen"
        case .settingsNotifications: "Mitteilungen"
        case .settingsNotificationsHelp: "Eine macOS-Mitteilung, wenn der Host auf Sie wartet — Werkzeugfreigabe, Frage, Durchsicht eines Plans, in einer beliebigen Sitzung — und wenn eine laufende Aufgabe endet. Der Wartezustand wird in jedem App-Zustand gemeldet; das Ende einer Aufgabe nur, solange diese App nicht im Vordergrund ist; ein Klick holt das Fenster nach vorn."
        case .settingsChannelHealthy: "Benachrichtigungskanal: mit der Host-API verbunden"
        case .settingsChannelUnauthorized: "Benachrichtigungskanal: wartet auf die Host-Anmeldeinformation — einmal die Seite öffnen, dann erholt er sich von selbst"
        case .settingsChannelReconnecting: "Benachrichtigungskanal: verbindet erneut…"
        case .settingsPageRefresh: "Seite automatisch erneuern"
        case .settingsPageRefreshHelp: "Lädt die Seite von selbst neu, wenn sie einen Tag lang läuft oder der WebKit-Content-Prozess ein Speicherlimit überschreitet, damit eine langlebige Anzeige keinen Renderspeicher anhäuft. Geschieht nur, wenn kein Fenster sichtbar ist, und nie, während der Host auf dich wartet."
        case .onboardingTitle: "Willkommen bei DSH Bezel"
        case .onboardingSubtitle: "Verbinden wir uns mit Ihrem ersten dsh-Host."
        case .onboardingSkip: "Überspringen — später einrichten"
        case .onboardingBack: "Zurück"
        case .onboardingDetecting: "Es wird nach einem laufenden dsh-Prozess gesucht…"
        case .onboardingRunningTitle: "Ein dsh-Prozess läuft"
        case .onboardingRunningHelp: "Binden Sie diese App daran, oder lassen Sie sie einen neuen Prozess starten und verwalten."
        case .onboardingNotRunningTitle: "Es läuft kein dsh-Prozess"
        case .onboardingNotRunningHelp: "Diese App kann einen für Sie starten und verwalten."
        case .onboardingMatchedProcesses: "Passende Prozesse:"
        case .onboardingChoiceBind: "An den laufenden Prozess binden"
        case .onboardingChoiceBindHelp: "Sie haben schon ein dsh, das seine Web-UI bereitstellt; diese App zeigt einfach darauf."
        case .onboardingChoiceManaged: "Neuen verwalteten Prozess starten"
        case .onboardingChoiceManagedHelp: "Der Prozess wird von dieser App gestartet und beim Beenden der App mitbeendet."
        case .onboardingBindLater: "Stattdessen an einen laufenden Prozess binden…"
        case .onboardingBindTitle: "An den laufenden Prozess binden"
        case .onboardingBindHelp: "Beide Werte stammen aus der Startausgabe dieses Prozesses — der Zeile `dsh web: http://…/?token=…`, die dort ausgegeben wurde, wo er gestartet wurde. Fügen Sie sie hier ein."
        case .onboardingButtonBind: "Binden und verbinden"
        case .onboardingManagedTitle: "Neues verwaltetes dsh starten"
        case .onboardingManagedHelp: "Ein verwalteter Prozess wird von dieser App gestartet und beim Beenden oder Trennen mitbeendet."
        case .onboardingManagedAuto: "Automatisch"
        case .onboardingManagedAutoHelp: "Findet ein installiertes dsh und startet es; fehlt es, wird es zuerst mit npm installiert."
        case .onboardingManagedManual: "Manuell"
        case .onboardingManagedManualHelp: "Sie geben den Startbefehl an; diese App führt ihn aus und beendet ihn beim Verlassen."
        case .onboardingContinue: "Fortfahren"
        case .onboardingAutoTitle: "Automatischer verwalteter Start"
        case .onboardingAutoFound: "dsh gefunden: {1}"
        case .onboardingAutoNotFound: "Es ist kein nutzbares dsh installiert."
        case .onboardingInstallHelp: "dsh kann automatisch mit npm installiert werden."
        case .onboardingInstallWillRun: "Wird ausgeführt: {1}"
        case .onboardingButtonInstall: "Installieren und starten"
        case .onboardingInstalling: "Wird installiert (das kann einige Minuten dauern)…"
        case .onboardingInstallFailed: "Die Installation ist fehlgeschlagen (Exit-Status {1}). Die Ausgabe unten nennt möglicherweise den Grund."
        case .onboardingInstallNoNPM: "Auch npm wurde nicht gefunden, dsh kann daher nicht automatisch installiert werden. Installieren Sie zuerst Node.js oder nutzen Sie den manuellen Modus."
        case .onboardingButtonStart: "Starten"
        case .onboardingStartFailed: "Der verwaltete Prozess konnte nicht gestartet werden."
        case .onboardingRetry: "Erneut versuchen"
        case .onboardingSwitchManual: "Stattdessen den manuellen Modus nutzen"
        case .onboardingManualTitle: "Manueller verwalteter Start"
        case .onboardingManualCommand: "Manueller verwalteter Start"
        case .launchCommandHelp: "Der Befehl muss eine Startzeile `dsh web: http://…` ausgeben, etwa `dsh --profile web --port 0 --no-open`. Er läuft über Ihre Login-Shell; diese App beendet ihn beim Verlassen."
        case .onboardingBindHostName: "Laufendes dsh"
        case .settingsFieldLaunchCommand: "Eigener Startbefehl (optional)"
        case .settingsFieldLaunchCommandPrompt: "leer lassen für den Standardaufruf"
        case .tabNewTab: "Neuer Tab"
        case .tabClose: "Tab schließen"
        }
    }

    /// Spanish wording for every message.
    var spanish: String {
        switch self {
        case .seedHostName: "dsh local"
        case .newHostName: "Host nuevo"
        case .untitledHost: "Host sin título"
        case .invalidAddress: "Dirección de Host no válida: {1}"
        case .statusNotConnected: "Sin conectar"
        case .statusLoading: "Cargando…"
        case .statusConnected: "Conectado"
        case .phaseLocating: "Buscando un dsh utilizable…"
        case .phaseStarting: "Iniciando el dsh local…"
        case .phaseCheckingPort: "Comprobando si ya hay un dsh en este puerto…"
        case .failureNoDSH: "No se encontró ningún dsh utilizable (se probaron {1} ubicaciones; consulta la salida de abajo)"
        case .failureLaunchFailed: "No se pudo iniciar dsh: {1}"
        case .failureExited: "dsh terminó (estado {1})"
        case .failureExitedBeforeStart: "dsh no pudo iniciarse (estado {1})"
        case .failureTimedOut: "dsh no se inició en {1} segundos"
        case .originHostSetting: "Seleccionar Host"
        case .originEnvironmentOverride: "BEZEL_DSH_PATH"
        case .originLoginShell: "shell de inicio de sesión"
        case .originAppPath: "PATH de la app"
        case .originWellKnown: "ubicaciones de instalación habituales"
        case .attemptSelected: "seleccionado"
        case .attemptNotExecutable: "no existe o no es ejecutable"
        case .attemptDidNotRun: "existe, pero `--version` no puede ejecutarse (normalmente falta node o npm en el PATH)"
        case .attemptSkipped: "no se probó: el tiempo asignado a la búsqueda se agotó antes"
        case .diagnosticChosen: "dsh: {1} (origen: {2})"
        case .diagnosticNoneFound: "No se encontró ningún dsh utilizable; se probaron todas las ubicaciones de abajo"
        case .diagnosticChildPATH: "PATH del proceso hijo:"
        case .toolbarSelectHost: "Seleccionar Host"
        case .toolbarReload: "Recargar"
        case .toolbarOpenInBrowser: "Abrir en el navegador"
        case .toolbarDisconnect: "Desconectar"
        case .menuManageHosts: "Gestionar Hosts…"
        case .buttonConnectSelected: "Conectar el Host seleccionado"
        case .buttonStartDSH: "Iniciar dsh"
        case .buttonRestartDSH: "Reiniciar dsh"
        case .buttonCheckHostSettings: "Revisar los ajustes del Host"
        case .connectPromptTitle: "Elige un Host de dsh al que conectarte"
        case .portConflictTitle: "El puerto ya está ocupado por un dsh en ejecución"
        case .portConflictMessage: "Ya hay un dsh ejecutándose en el puerto {1} ({2}). Puedes enlazarte a él directamente; esta app no iniciará otro."
        case .portConflictBind: "Enlazar al dsh en ejecución"
        case .portConflictCancel: "Cancelar"
        case .menuFindTitle: "Buscar"
case .menuFind: "Buscar…"
        case .menuFindNext: "Siguiente"
        case .menuFindPrevious: "Anterior"
        case .menuUseSelectionForFind: "Usar la selección para buscar"
        case .findMatchesFound: "{1} resultados"
        case .settingsTabHosts: "Hosts"
        case .settingsTabGeneral: "General"
        case .settingsLanguage: "Idioma"
        case .settingsLanguageHelp: "Solo afecta a la interfaz de esta app. No cambia el idioma de la interfaz web del Host, que es un ajuste propio del Host."
        case .settingsLanguageRestartNote: "La barra de menús adopta el nuevo idioma en el próximo inicio; todo lo demás cambia de inmediato."
        case .settingsRestartNow: "Reiniciar ahora"
        case .settingsSelectOrCreate: "Selecciona o crea un Host"
        case .settingsNewHost: "Host nuevo"
        case .settingsRemoveHost: "Quitar el Host"
        case .settingsFieldName: "Nombre"
        case .settingsFieldAddress: "Dirección"
        case .settingsFieldToken: "Token de inicio (opcional)"
        case .settingsFieldTokenPrompt: "el ?token=… de la salida de inicio"
        case .settingsTokenHelp: "El token se usa una sola vez, para obtener la cookie firmada válida durante 30 días. Si la cookie caduca o se reemplaza el proceso del Host, vuelve a pegar la dirección completa que muestra `dsh web`."
        case .settingsToggleManaged: "Iniciar un dsh local para este Host"
        case .settingsFieldExtraArguments: "Argumentos adicionales"
        case .settingsFieldDSHPath: "Ruta del ejecutable dsh"
        case .settingsFieldDSHPathPrompt: "déjalo vacío para buscarlo automáticamente"
        case .settingsManagedHelp: "Ejecuta `dsh --profile <profile> --port 0 --no-open`: el sistema elige el puerto y la URL se lee de la salida del proceso hijo. Una app abierta desde el Finder no ve el PATH de tu terminal, así que la búsqueda pregunta al shell de inicio de sesión y prueba cada candidato con `--version`; si ninguno funciona, pon arriba la salida de `command -v dsh`."
        case .settingsButtonConnect: "Conectar con este Host"
        case .settingsInvalidAddress: "Dirección no válida"
        case .settingsConfigFile: "Archivo de configuración"
        case .settingsConfigHelp: "Los marcadores, el Host seleccionado y el idioma están todos en este archivo. Se lee al iniciar, así que los cambios hechos con la app cerrada se aplican la próxima vez que se abra."
        case .settingsWriteFailed: "No se pudo escribir el archivo de configuración: {1}"
        case .settingsUnreadableData: "El archivo de configuración no se puede descodificar, así que se usa el Host predeterminado. El archivo en sí no se ha sobrescrito."
        case .settingsNewerFile: "Este archivo de configuración lo escribió una versión más reciente de la app (versión {1}). Se usa en la medida en que esta versión lo entiende, pero no se reescribe nada, por lo que los cambios hechos aquí no se conservarán."
        case .errorCredentialRejected: "El Host rechazó esta credencial: el token no es válido y no hay ninguna cookie utilizable"
        case .notificationAttentionApproval: "Se necesita aprobación: una llamada de herramienta espera tu decisión"
        case .notificationAttentionQuestion: "El Host hizo una pregunta y espera tu respuesta"
        case .notificationAttentionPlan: "Hay un plan esperando tu revisión"
        case .notificationTaskFinished: "La tarea ha terminado"
        case .settingsNotifications: "Notificaciones"
        case .settingsNotificationsHelp: "Una notificación de macOS cuando el Host te espera —aprobación de una herramienta, una pregunta, la revisión de un plan, en cualquier sesión— y cuando termina una tarea en curso. Sea cual sea el estado de la app, una espera siempre se notifica; el fin de una tarea solo mientras la app no está en primer plano; al hacer clic, la ventana pasa al frente."
        case .settingsChannelHealthy: "Canal de notificaciones: conectado a la API del Host"
        case .settingsChannelUnauthorized: "Canal de notificaciones: esperando la credencial del Host — abre la página una vez y se recuperará solo"
        case .settingsChannelReconnecting: "Canal de notificaciones: reconectando…"
        case .settingsPageRefresh: "Renovación automática de la página"
        case .settingsPageRefreshHelp: "Recarga la página por su cuenta cuando lleva un día abierta, o cuando el proceso de contenido de WebKit supera un límite de memoria, para que una pantalla de larga duración no acumule memoria de renderizado. Ocurre solo cuando ninguna ventana está visible, y nunca mientras el Host espera tu respuesta."
        case .onboardingTitle: "Bienvenido a DSH Bezel"
        case .onboardingSubtitle: "Vamos a conectar con tu primer Host de dsh."
        case .onboardingSkip: "Omitir: configurar más tarde"
        case .onboardingBack: "Atrás"
        case .onboardingDetecting: "Comprobando si hay un proceso dsh en ejecución…"
        case .onboardingRunningTitle: "Hay un proceso dsh en ejecución"
        case .onboardingRunningHelp: "Vincula esta app a él, o deja que la app inicie y gestione uno nuevo."
        case .onboardingNotRunningTitle: "No hay ningún proceso dsh en ejecución"
        case .onboardingNotRunningHelp: "Esta app puede iniciar y gestionar uno por ti."
        case .onboardingMatchedProcesses: "Procesos coincidentes:"
        case .onboardingChoiceBind: "Vincular al proceso en ejecución"
        case .onboardingChoiceBindHelp: "Ya tienes un dsh sirviendo su interfaz web; esta app solo apunta a él."
        case .onboardingChoiceManaged: "Iniciar un nuevo proceso gestionado"
        case .onboardingChoiceManagedHelp: "El proceso lo inicia esta app y lo termina al salir."
        case .onboardingBindLater: "Vincular a un proceso en ejecución en su lugar…"
        case .onboardingBindTitle: "Vincular al proceso en ejecución"
        case .onboardingBindHelp: "Los dos valores vienen de la salida de inicio de ese proceso: la línea `dsh web: http://…/?token=…` que imprimió donde se inició. Pégalos aquí."
        case .onboardingButtonBind: "Vincular y conectar"
        case .onboardingManagedTitle: "Iniciar un nuevo dsh gestionado"
        case .onboardingManagedHelp: "Un proceso gestionado lo inicia esta app y se termina cuando la app se cierra o se desconecta."
        case .onboardingManagedAuto: "Automático"
        case .onboardingManagedAutoHelp: "Busca un dsh instalado y lo inicia; si falta, primero lo instala con npm."
        case .onboardingManagedManual: "Manual"
        case .onboardingManagedManualHelp: "Tú proporcionas el comando de inicio; esta app lo ejecuta y lo termina al salir."
        case .onboardingContinue: "Continuar"
        case .onboardingAutoTitle: "Inicio gestionado automático"
        case .onboardingAutoFound: "dsh encontrado: {1}"
        case .onboardingAutoNotFound: "No hay ningún dsh utilizable instalado."
        case .onboardingInstallHelp: "dsh se puede instalar automáticamente con npm."
        case .onboardingInstallWillRun: "Se ejecutará: {1}"
        case .onboardingButtonInstall: "Instalar e iniciar"
        case .onboardingInstalling: "Instalando (puede tardar unos minutos)…"
        case .onboardingInstallFailed: "La instalación falló (estado de salida {1}). La salida de abajo puede explicar por qué."
        case .onboardingInstallNoNPM: "Tampoco se encontró npm, así que dsh no se puede instalar automáticamente. Instala primero Node.js o usa el modo manual."
        case .onboardingButtonStart: "Iniciar"
        case .onboardingStartFailed: "El proceso gestionado no pudo iniciarse."
        case .onboardingRetry: "Reintentar"
        case .onboardingSwitchManual: "Usar el modo manual en su lugar"
        case .onboardingManualTitle: "Inicio gestionado manual"
        case .onboardingManualCommand: "Comando de inicio"
        case .launchCommandHelp: "El comando debe imprimir una línea de inicio `dsh web: http://…`, como `dsh --profile web --port 0 --no-open`. Se ejecuta a través de tu shell de inicio de sesión; esta app lo termina al salir."
        case .onboardingBindHostName: "dsh en ejecución"
        case .settingsFieldLaunchCommand: "Comando de inicio personalizado (opcional)"
        case .settingsFieldLaunchCommandPrompt: "déjalo vacío para la invocación estándar"
        case .tabNewTab: "Nueva pestaña"
        case .tabClose: "Cerrar pestaña"
        }
    }
}
