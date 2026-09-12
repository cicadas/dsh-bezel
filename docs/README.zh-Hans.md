# DSH Bezel

[English](../README.md) · **简体中文** · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md)

yet-another-dsh-for-mac。一个原生 macOS 外壳，把 dsh Host 自己的 Web UI 直接装进 `WKWebView`，然后在显示之外只补一个外壳能正当补的东西：**选择连哪个 dsh**、**知道显示正在叫你**、以及**自己的界面语言**。

## 为什么是外壳，而不是重实现协议

dsh 的 Web UI 不是可以打进 App 里的静态前端——它是 Host 自己伺服的完整应用：

- SPA 由 Host 的 frontend-static 席位伺服；
- 每个 `dsh.client` 插件的浏览器包从 `/plugins/<id>/client.js` 伺服；
- `window.__DSH_BOOT__` 引导载荷由 Host 在每次渲染首页时注入。

所以"连哪个 dsh"在实现上就归结为"`WKWebView` 加载哪个 URL"。买到的是**零协议漂移**：会话渲染、审批、计划、目标、工具卡片、附件、设置、模型选择、第三方浏览器插件，全部自动跟随 Host 版本。本项目永远不需要理解 `/api`、`/api/remote.mux` 或任何事件类型。

## 快速开始

```sh
swift build --disable-sandbox   # 编译（这个标志只在 DSH harness 下需要）
swift test --disable-sandbox    # 连接模型与页面信号的单元测试
./scripts/make-app.sh           # 产出 build/DSH Bezel.app
open "build/DSH Bezel.app"
```

`swift run dsh-bezel` 也行，但那是裸可执行文件：没有 bundle，`Info.plist` 里的 ATS 例外不生效，Cookie 与偏好的归属不稳定，macOS 也不会投递通知。正经使用请用 `.app`。

## 首次启动引导

首次启动打开的是一段简短的引导，而不是主窗口。它会侦测是否已有 DSH 程序在伺服 Web UI，并据此给出选项：

- **绑定现有程序**——把本应用指向一个你自己启动的 `dsh`，贴上它启动输出里的位址和 token。
- **代管启动一个新的**——本应用运行子程序，退出时终止它。*自动*会寻找已安装的 `dsh`（找不到时提供经 npm 安装，那需要 Node.js）；*手动*执行你提供的启动命令，只要它打印 `dsh web: http://…` 启动行。

跳过引导会落在连线提示上，一步之遥；引导只在配置文件被删除后才会回来。

## 界面语言

界面默认英语，与 macOS 自身的语言设置无关。设置窗口 →「通用」→「语言」可切换为简体中文、繁體中文、日本語、Français、Deutsch 或 Español，选择写进下面那个配置文件，重启后保持。

七种语言全部住在同一个文件里，走穷举 switch，所以一条消息不可能只带其中几种语言：漏掉一条翻译会让构建失败，而不是在英文界面里留下一条中文。那个文件也承载运行期诊断的措辞——它们以结构化值传递、显示时才渲染成文字——所以切换语言会重绘已经在屏幕上的失败信息，而不是让它停留在产生时的语言里。

唯一不能在会话中切换的是原生菜单栏：macOS 在启动时按 bundle 的本地化绘制它。每次启动，应用会在构建 UI 之前把配置的语言镜像进 `AppleLanguages`，且 bundle 为每种支持的语言都带了 `.lproj`，于是菜单栏在下次启动时跟随设置。所选语言和菜单栏不一致时，设置里就为此给出一个重启按钮。

这项设置只覆盖本应用自己的界面。Host 的 Web UI 由 Host 伺服，语言由它自己决定。

## 通知

表圈在显示之外唯一可以正当添加的能力，是知道显示正在叫你。两个时刻值得叫你：Host 在等你决定（工具审批、提问、计划审阅），或者正在运行的任务刚结束。下面的一切都是**页面监控**：这两件事，本应用都是从你正看着的同一个页面上学来的——读的是 Host 自己的 Web UI 恰好会为这些情形渲染的东西——不拦截任何流量、不读线上数据、不改动页面里的任何东西。

### 页面监控

**注入。** 一段很小的观察脚本——纯 JavaScript、只读——注册为 WebKit 用户脚本，随 `WKWebView` 加载的每个页面同行，在文档结束时注入。一段守卫保证被重复注入的脚本（重新加载会重跑用户脚本）不会叠加出多个定时器。

**轮询。** 脚本每秒取一份快照；每一趟只是几次 `querySelector` 调用。用朴素的轮询而不是 `MutationObserver`，因为轮询不会漏掉一个在两次变更之间挂载又卸载的面板，而朴素的观察者摘要会。

**一份快照读什么**——只读 Host 自己的 Web UI 渲染的标记：

| 信号 | 标记 | 含义 |
| --- | --- | --- |
| 等待面板 | `data-approval-key` / `data-question-key` / `data-plan-review-key` | Host 卡在审批、提问或计划审阅上 |
| 回合结束 | 最终答案下方操作栏（复制、fork、用量、反馈）上的 `data-turn-tail` | Host 自己的"本轮结束"标记——在回合的 `turn/end` 事件到达那一刻才发布，所以"任务已结束"的含义与页面完全一致，而不是从"流式标记安静了"推测出来的 |
| 任务名 | 该行携带的回合编号定位发起这一轮的那条用户消息 | 通知告诉你**是哪个任务**结束了——用你自己的原话 |
| 还是同一个会话吗 | 最新几条内容行的 `data-chat-anchor-key` | 切换会换掉每一行，而回合结束只是在其下方添一行——所以切换会话绝不会伪装成"任务已结束" |
| 会话名 | 选中的侧栏行，或 `document.title`（`"<会话> — <产品>"`） | 每条通知都指名它的会话 |
| 后台会话 | 侧栏行的 `data-state` 状态点 | 运行中 / 在等你 / 已结束未看过 |

**从快照到事件。** 脚本每秒把快照经一条私有的桥接通道（`window.webkit.messageHandlers`）发出去；应用解码之后，由一个纯的、带单元测试的检测器推导出值得通知的转变：等待出现、回合结束标记在上方各行仍然站立时变化、状态点翻转。加载后的第一份快照只是基线——现状是状态，不是新闻；间隔之后第一次看到的状态点是历史，不是事件。

### 没有人显示的后台

不在当前页面上的任务——同一 Host 里后台运行的其他会话——借唯一能看到它们的那块表面覆盖：侧栏。侧栏的会话行带着 Host 自己维护的实时状态点（`data-state`）：运行中、在等你、或"已结束但还没看过"——最后这个正是 Host 自己的"完成提醒"，恰好在某个后台会话从运行转为空闲、而没人打开过它时点亮。状态点的边沿变成一条指名道姓的通知。

侧栏只渲染它自己的视图状态肯显示的东西——折叠的工作区分组一行会话都不渲染，展开的分组也只显示最近五个——所以显示页自己的侧栏并不是后台的全部。一个隐藏的第二个 `WKWebView` 加载同一个 Host 页面（独立的非持久存储、拷贝显示页的 Cookie、地址去掉一次性的 token），扫描前把每个分组和"N more"全部展开：没有人看那页，它的点击只写自己的视图状态。它不恢复任何选中——什么也不打开——所以 Host 按客户端维护的完成点亮起时不被它清掉。探测页活着时，它的行就是后台的真相：它每秒发一份快照，超过十五秒旧的行让位给显示页自己的侧栏，安静超过三十秒的页面会带着新拷贝的 Cookie 重新加载。

### 投递规则

快照何时变成 macOS 通知，按事件类别分两条规则。召唤——Host 在等你的输入或确认，无论在当前页面还是后台会话——**任何情况都会投递**：前台、后台、最小化都一样，因为它卡着 Host 直到被回应，而眼前的页面并不能覆盖所有来源。任务结束则是状态汇报：本应用在前台且窗口立着时，页面自己就是通知，横幅只会重复屏幕上已有的内容。点通知会把窗口带到前面，最小化在 Dock 里的话会一并还原。

通知默认开启；设置 →「通用」里有开关，系统的权限对话框只在首次启动问一次。macOS 只从 App bundle 投递通知——`swift run` 的裸可执行文件既不询问也不会通知。

## 记住了什么

应用知道的一切都在一个 JSON 文件里：

```
~/Library/Application Support/dsh-bezel/config.json
```

里面有 Host 书签及其全部设置、选择器停在哪个书签、WebView 上次连的是哪个、以及界面语言。启动时读这个文件，并**自动重连上次连接的那个 Host**——打开应用就等于回到上次的位置；托管 Host 每次都重新启动，因为它的端口与 token 每次都是新的。签名 Cookie（`dsh-auth`）由 WebKit 自己的数据存储单独记住，所以重连不必再贴 token。

用文件而不用 `UserDefaults`，是为了能读、能改、能拷去别的机器、能进版本控制。写入时 pretty-print、键排序、斜杠不转义，正是为了让它的 diff 可读；经临时文件原子落盘，写到一半崩溃也截不断它；权限 `0600`，因为书签里可能有启动 token。`BEZEL_CONFIG` 可以把它指到别的路径。

解码逐字段、足够宽容：不认识的键忽略，类型不对的标量落回默认值，旧版本构建写的书签（缺后来才加的字段）照常加载。完全解析不了的文件会在设置里报告，并且**原样保留**——绝不覆写——手改时打错一个字、或者新版构建写的文件，都还能救回来。删掉这个文件就是重置。你自己起的名字是你的数据，任何语言下都按原样显示；只有首次播种的书签名跟随当前语言。窗口大小与位置不在这个文件里：SwiftUI 自己记。

## 连接模型

一个 Host 就是一条书签，要紧的字段四个：**名称、位址（origin）、启动 token（选填）、是否由本应用托管**。

**外部 Host（不托管）**：填 `http://host:port`。如果那个 Host 还没给这个浏览器发过 Cookie，把 `dsh web` 启动输出的完整位址贴进"启动 token"，或者带着 `?token=` 在浏览器里开一次再回到本应用（Cookie 按授权方在本应用的 WebKit 数据存储内共享）。

**托管 Host**：本应用运行

```sh
dsh --profile web --port 0 --no-open
```

端口 `0` 交给系统分配，URL 从子程序 stdout 的 `dsh web: http://127.0.0.1:PORT/?token=…` 行解析。退出应用会终止该子程序（「断开连接」按钮也一样）。30 秒内没等到那一行就判定超时并终止子程序，界面不会永远停在"启动中"。

**寻找 `dsh`**：从 Finder 双击启动的应用继承 launchd 的最小 PATH（`/usr/bin:/bin:/usr/sbin:/sbin`），里面既没有 node 也没有 npm——而真机上几乎每个 `dsh` 都是需要解释器的包装器（`#!/usr/bin/env node`、`npm exec …`、或 DSH Desktop 的运行时 shim）。所以"文件存在且有 x 位"远远不足以称为可用。搜索按这个顺序进行，每个候选都真用 `dsh --version` 跑一次，只有成功的才交给子程序：

1. Host 设置里的"dsh 可执行文件路径"
2. `BEZEL_DSH_PATH` 环境变量
3. 登入 shell 的 `command -v dsh`
4. 应用自身 PATH 上的 `dsh`
5. 常见安装位置：`~/.local/bin`、`~/bin`、`/opt/homebrew/bin`、`/usr/local/bin`、`~/.npm-global/bin`、`~/.bun/bin`、`/opt/anaconda3/bin`、……

第 3 步问的是**交互式**登入 shell（`zsh -l -i -c`，失败退到 `-l -c`）：放着 `node`/`npm` 的目录通常写在 `~/.zshrc` 里，非交互的 `zsh -l -c` 永远不读它——这正是 GUI 应用的 PATH 和用户终端对不上的原因。探测用一行哨兵把 rc 文件的杂音和答案分开，超时 5 秒。

子程序的 PATH 是：登入 shell 的 PATH → 应用继承的 PATH → 解释器目录，去重合并。注意只注入**解释器目录**——绝不注入像 `~/bin`、`~/.local/bin` 这种可能住着*另一个* `dsh` 的目录：有些包装器自己会扫 PATH 并听命于找到的东西（DSH Desktop 的 shim 就这样），把另一个包装器放上 PATH 等于把启动交给它，而不是用 shim 自带的运行时。

所有候选都失败时，连线提示会列出试过的每个位置和失败原因（不存在，或 `--version` 跑不起来）。

**凭据语义**：`GET /?token=…` 由 Host 换成一张签名 Cookie，30 天有效（`dsh-auth-<hash(authority)>`，`HttpOnly`）。签名密钥持久化在 Host 的凭据里，所以 Cookie 活得过 Host 重启；没有 Cookie 时才需要 token。Cookie 有效时，Host 的首页授权把任何 `?token=` 请求 303 重定向到干净的 `/`，所以把 token 留在地址里是安全的——而且只要 Cookie 还在，过期的 token 也不会变成 401。两个都不行时，页面会明说。

**多个 Host**：Cookie 名里带授权方哈希，几个 Host 的会话在同一个 WebKit 数据存储里并存；切换 Host 不过是切换 URL。

## 设置

设置窗口（工具栏 Host 菜单 →「管理 Host…」，或 ⌘,）有两个标签页。

**Host**——增删改书签：

| 字段 | 含义 |
| --- | --- |
| 名称 | 显示在选择器里；留空则用位址 |
| 位址 | Host 的 origin，例如 `http://127.0.0.1:3080` |
| 启动 token | `dsh web` 输出里的 `?token=…`；仅在没有 Cookie 时需要 |
| 由本应用启动本地 dsh | 本应用产生子程序 |
| profile | 托管模式的 `--profile`，默认 `web` |
| 额外参数 | 追加到 `dsh` 调用后，例如 `--trusted-host dsh.internal` |
| 自定义启动命令 | 托管模式下整体替换调用；必须打印 `dsh web: http://…` 行 |
| dsh 可执行文件路径 | 托管模式运行哪个 `dsh`；留空表示搜索（见"寻找 `dsh`"） |

**通用**——属于应用而非某个 Host 的偏好：

| 字段 | 含义 |
| --- | --- |
| 语言 | 界面语言：英语（默认）、简体中文、繁體中文、日本語、Français、Deutsch 或 Español |
| 通知 | 等待中的 Host 与结束的任务的 macOS 通知；默认开启 |
| 配置文件 | 配置存于何处；显示路径，选中可以拷贝 |

书签与其余配置随编辑写入那个文件；写入、迁移与保护的方式见上面的"记住了什么"。

## 布局

```
Sources/BezelCore/          连接与信号模型（无 SwiftUI，可单测）
  DSHHost.swift             Host 书签：origin 归一化、token→URL、参数拆分
  AppConfig.swift           两次启动之间记住的一切，作为一个值
  ConfigFile.swift          JSON 文件：位置、原子写入、宽容读取
  ConfigStore.swift         这个值的唯一持有者：加载、编辑、持久化
  Localization.swift        七种语言，以及每条消息的全部译法
  DSHDiscovery.swift        寻找可用的 dsh：登入 shell 探测、PATH 合并、候选、可运行性
  LocalHostRunner.swift     托管子程序：异步发现、启动行解析、超时、退出诊断
  DSHProcessScan.swift      扫描进程找运行中的 DSH（引导的侦测步骤）
  DSHInstall.swift          经 npm 安装 dsh（引导的自动路径）
  PageSignals.swift         页面快照、观察/探测脚本、事件检测器
  ShellCommand.swift        带超时的一次性 shell 调用
  BoundedProcess.swift      输出有界、事后可读的子程序
  OneShotCommand.swift      小的进程运行辅助
  JSONValue.swift           配置经它解码的宽容 JSON 树
Sources/dsh-bezel/          应用与 UI
  BezelApp.swift            入口、语言镜像、--dump-config / --dump-hosts 冒烟入口
  Model/AppState.swift      配置/子程序/WebView/探测页的粘合，连线状态，通知措辞
  Model/Notifier.swift      macOS 通知投递与两条投递规则
  Web/WebView.swift         WKWebView 宿主、导航状态报告、观察脚本的通道
  Web/SidebarProbe.swift    读取完整侧栏的隐藏页面
  UI/MainView.swift         工具栏、Host 选择器、连线提示、错误横幅
  UI/OnboardingView.swift   首次启动引导
  UI/SettingsView.swift     Host 管理与应用偏好（两个标签页）
Tests/BezelCoreTests/       位址归一化、启动行解析、配置文件与存储、本地化、页面信号
```

## 已知约束

- **纯 http 与 ATS**：Host 可能是局域网里的 `http://`，所以 `Resources/Info.plist` 设了 `NSAllowsArbitraryLoadsInWebContent`（只放宽 WebView 内容；应用自身的请求仍在 ATS 之下）。前置一个 `https://` 反向代理就不需要它了。
- **远程 Host 得接纳这个客户端**：dsh 的 `/api` 有一道浏览器信任栏，接受回环、部署推得的局域网 IP 字面量、或经 `--trusted-host` 声明的授权方。要用域名连远程 Host，那个 Host 必须带 `--trusted-host` 启动。另注意 `dsh web` 的 CLI 拒绝 `--host 0.0.0.0`；要服务到本机之外得在配置层写 `host: '0.0.0.0'`。
- **无 App Sandbox**：托管模式要产生 `dsh`，而 harness 的会话工具本来就在用户机器上跑命令，沙箱会破坏那个信任模型。只连外部 Host 的话可以自己加沙箱和 `com.apple.security.network.client`。
- **范围**：本应用不给对话本身添加任何功能——Web UI 有什么就是什么。它在显示之外补的是 Host 选择器、通知、语言和首次启动引导。
- **前置条件**：一个能伺服 Web UI 的 dsh Host。`dsh web` 的启动行与 `?token=` 兑换自 0.1.5-rc.1 起就是稳定的。

## 与 dsh-for-mac 的关系

`dsh-for-mac` 走另一条路：用 Swift 重实现线上协议（一元 RPC + `/api/remote.mux` + 事件流），换来完全原生的交互，代价是自己追踪协议、自己扛漂移。本项目刻意不这么做。两者可以并存；本应用确实补的原生形状的东西——通知、跟随语言的菜单栏——都包在页面外面，不碰连接模型。

## 开发

```sh
swift build --disable-sandbox
swift test --disable-sandbox
swift run dsh-bezel --dump-config   # 配置文件：路径，或它装着什么
swift run dsh-bezel --dump-hosts    # 只看保存的书签
```

裸可执行文件和 bundle 共用一个配置文件，所以 `swift run` 做实验用的就是真实配置——除非 `BEZEL_CONFIG` 另有指向。在 DSH harness 下构建需要 `--disable-sandbox`，因为它嵌不进自己的沙箱。
