# DSH Bezel

[English](../README.md) · [简体中文](README.zh-Hans.md) · **繁體中文** · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md)

yet-another-dsh-for-mac。一個原生 macOS 外殼，把 dsh Host 自己的 Web UI 直接裝進 `WKWebView`，然後在顯示之外只補一個外殼能正當補的東西：**選擇連哪個 dsh**、**知道顯示正在叫你**、以及**自己的介面語言**。

## 為什麼是外殼，而不是重實作協定

dsh 的 Web UI 不是可以打進 App 裡的靜態前端——它是 Host 自己伺服的完整應用：

- SPA 由 Host 的 frontend-static 席位伺服；
- 每個 `dsh.client` 外掛的瀏覽器套件從 `/plugins/<id>/client.js` 伺服；
- `window.__DSH_BOOT__` 引導承載由 Host 在每次渲染首頁時注入。

所以「連哪個 dsh」在實作上就歸結為「`WKWebView` 載入哪個 URL」。買到的是**零協定漂移**：對話渲染、核准、計畫、目標、工具卡片、附件、設定、模型選擇、第三方瀏覽器外掛，全部自動跟隨 Host 版本。本專案永遠不需要理解 `/api`、`/api/remote.mux` 或任何事件型別。

## 快速開始

```sh
swift build --disable-sandbox   # 編譯（這個旗標只在 DSH harness 下需要）
swift test --disable-sandbox    # 連線模型與頁面訊號的單元測試
./scripts/make-app.sh           # 產出 build/DSH Bezel.app
open "build/DSH Bezel.app"
```

`swift run dsh-bezel` 也行，但那是裸可執行檔：沒有 bundle，`Info.plist` 裡的 ATS 例外不生效，Cookie 與偏好的歸屬不穩定，macOS 也不會投遞通知。正經使用請用 `.app`。

## 首次啟動引導

首次啟動開啟的是一段簡短的引導，而不是主視窗。它會偵測是否已有 DSH 程序在伺服 Web UI，並據此給出選項：

- **綁定現有程序**——把本應用程式指向一個你自己啟動的 `dsh`，貼上它啟動輸出裡的位址和 token。
- **代管啟動一個新的**——本應用程式執行子程序，結束時終止它。*自動*會尋找已安裝的 `dsh`（找不到時提供經 npm 安裝，那需要 Node.js）；*手動*執行你提供的啟動命令，只要它列印 `dsh web: http://…` 啟動行。

略過引導會落在連線提示上，一步之遙；引導只在設定檔被刪除後才會回來。

## 介面語言

介面預設英語，與 macOS 自身的語言設定無關。設定視窗 →「一般」→「語言」可切換為簡體中文、繁體中文、日本語、Français、Deutsch 或 Español，選擇寫進下面那個設定檔，重新啟動後保持。

七種語言全部住在同一個檔案裡，走窮舉 switch，所以一則訊息不可能只帶其中幾種語言：漏掉一條翻譯會讓建置失敗，而不是在英文介面裡留下一條中文。那個檔案也承載執行期診斷的措辭——它們以結構化值傳遞、顯示時才渲染成文字——所以切換語言會重繪已經在螢幕上的失敗資訊，而不是讓它停留在產生時的語言裡。

唯一不能在作業階段中切換的是原生選單列：macOS 在啟動時按 bundle 的在地化繪製它。每次啟動，應用程式會在建構 UI 之前把設定的語言鏡射進 `AppleLanguages`，且 bundle 為每種支援的語言都帶了 `.lproj`，於是選單列在下次啟動時跟隨設定。所選語言和選單列不一致時，設定裡就為此給出一個重新啟動按鈕。

這項設定只涵蓋本應用程式自己的介面。Host 的 Web UI 由 Host 伺服，語言由它自己決定。

## 通知

錶圈在顯示之外唯一可以正當添加的能力，是知道顯示正在叫你。兩個時刻值得叫你：Host 在等你決定（工具核准、提問、計畫審閱），或者正在執行的任務剛結束。下面的一切都是**頁面監控**：這兩件事，本應用程式都是從你正看著的同一個頁面上學來的——讀的是 Host 自己的 Web UI 恰好會為這些情形渲染的東西——不攔截任何流量、不讀線上資料、不改動頁面裡的任何東西。

### 頁面監控

**注入。** 一段很小的觀察指令碼——純 JavaScript、唯讀——註冊為 WebKit 使用者指令碼，隨 `WKWebView` 載入的每個頁面同行，在文件結束時注入。一段守衛保證被重複注入的指令碼（重新載入會重跑使用者指令碼）不會疊加出多個計時器。

**輪詢。** 指令碼每秒取一份快照；每一趟只是幾次 `querySelector` 呼叫。用樸素的輪詢而不是 `MutationObserver`，因為輪詢不會漏掉一個在兩次變更之間掛載又卸載的面板，而樸素的觀察者摘要會。

**一份快照讀什麼**——只讀 Host 自己的 Web UI 渲染的標記：

| 訊號 | 標記 | 含義 |
| --- | --- | --- |
| 等待面板 | `data-approval-key` / `data-question-key` / `data-plan-review-key` | Host 卡在核准、提問或計畫審閱上 |
| 回合結束 | 最終答案下方操作列（複製、fork、用量、回饋）上的 `data-turn-tail` | Host 自己的「本輪結束」標記——在回合的 `turn/end` 事件到達那一刻才發布，所以「任務已結束」的含義與頁面完全一致，而不是從「串流標記安靜了」推測出來的 |
| 任務名 | 該列攜帶的回合編號定位發起這一輪的那條使用者訊息 | 通知告訴你**是哪個任務**結束了——用你自己的原話 |
| 還是同一個對話嗎 | 最新幾條內容列的 `data-chat-anchor-key` | 切換會換掉每一列，而回合結束只是在其下方添一列——所以切換對話絕不會偽裝成「任務已結束」 |
| 對話名 | 選中的側欄列，或 `document.title`（`"<對話> — <產品>"`） | 每則通知都指名它的對話 |
| 背景對話 | 側欄列的 `data-state` 狀態點 | 執行中 / 在等你 / 已結束未看過 |

**從快照到事件。** 指令碼每秒把快照經一條私有的橋接通道（`window.webkit.messageHandlers`）送出去；應用程式解碼之後，由一個純的、帶單元測試的檢測器推導出值得通知的轉變：等待出現、回合結束標記在上方各列仍然站立時變化、狀態點翻轉。載入後的第一份快照只是基線——現況是狀態，不是新聞；間隔之後第一次看到的狀態點是歷史，不是事件。

### 沒有人顯示的背景

不在目前頁面上的任務——同一 Host 裡背景執行的其他對話——借唯一能看到它們的那塊表面涵蓋：側欄。側欄的對話行帶著 Host 自己維護的即時狀態點（`data-state`）：執行中、在等你、或「已結束但還沒看過」——最後這個正是 Host 自己的「完成提醒」，恰好在某個背景對話從執行轉為閒置、而沒人開過它時亮起。狀態點的邊沿變成一則指名道姓的通知。

側欄只渲染它自己的檢視狀態肯顯示的東西——折疊的工作區分組一列對話都不渲染，展開的分組也只顯示最近五個——所以顯示頁自己的側欄並不是背景的全部。一個隱藏的第二個 `WKWebView` 載入同一個 Host 頁面（獨立的非持續性儲存、拷貝顯示頁的 Cookie、位址去掉一次性的 token），掃描前把每個分組和「N more」全部展開：沒有人看那頁，它的點按只寫自己的檢視狀態。它不還原任何選取——什麼也不開啟——所以 Host 按用戶端維護的完成點亮起時不被它清掉。探測頁活著時，它的列就是背景的真相：它每秒送一份快照，超過十五秒舊的列讓位給顯示頁自己的側欄，安靜超過三十秒的頁面會帶著新拷貝的 Cookie 重新載入。

### 投遞規則

快照何時變成 macOS 通知，按事件類別分兩條規則。召喚——Host 在等你的輸入或確認，無論在目前頁面還是背景對話——**任何情況都會投遞**：前景、背景、最小化都一樣，因為它卡著 Host 直到被回應，而眼前的頁面並不能涵蓋所有來源。任務結束則是狀態回報：本應用程式在前景且視窗立著時，頁面自己就是通知，橫幅只會重複螢幕上已有的內容。點按通知會把視窗帶到前面，最小化在 Dock 裡的話會一併還原。

通知預設開啟；設定 →「一般」裡有開關，系統的權限對話框只在首次啟動問一次。macOS 只從 App bundle 投遞通知——`swift run` 的裸可執行檔既不詢問也不會通知。

## 記住了什麼

應用程式知道的一切都在一個 JSON 檔案裡：

```
~/Library/Application Support/dsh-bezel/config.json
```

裡面有 Host 書籤及其全部設定、選擇器停在哪個書籤、WebView 上次連的是哪個、以及介面語言。啟動時讀這個檔案，並**自動重連上次連線的那個 Host**——開啟應用程式就等於回到上次的位置；代管 Host 每次都重新啟動，因為它的連接埠與 token 每次都是新的。簽署 Cookie（`dsh-auth`）由 WebKit 自己的資料儲存單獨記住，所以重連不必再貼 token。

用檔案而不用 `UserDefaults`，是為了能讀、能改、能拷去別的機器、能進版本控制。寫入時 pretty-print、鍵排序、斜線不轉義，正是為了讓它的 diff 可讀；經暫存檔原子落盤，寫到一半崩潰也截不斷它；權限 `0600`，因為書籤裡可能有啟動 token。`BEZEL_CONFIG` 可以把它指到別的路徑。

解碼逐欄位、足夠寬容：不認識的鍵忽略，型別不對的純量落回預設值，舊版本建置寫的書籤（缺後來才加的欄位）照常載入。完全解析不了的檔案會在設定裡報告，並且**原樣保留**——絕不覆寫——手改時打錯一個字、或者新版建置寫的檔案，都還能救回來。刪掉這個檔案就是重設。你自己取的名字是你的資料，任何語言下都按原樣顯示；只有首次播種的書籤名跟隨目前語言。視窗大小與位置不在這個檔案裡：SwiftUI 自己記。

## 連線模型

一個 Host 就是一條書籤，要緊的欄位四個：**名稱、位址（origin）、啟動 token（選填）、是否由本應用程式代管**。

**外部 Host（不代管）**：填 `http://host:port`。如果那個 Host 還沒給這個瀏覽器發過 Cookie，把 `dsh web` 啟動輸出的完整位址貼進「啟動 token」，或者帶著 `?token=` 在瀏覽器裡開一次再回到本應用程式（Cookie 按授權方在本應用程式的 WebKit 資料儲存內共享）。

**代管 Host**：本應用程式執行

```sh
dsh --profile web --port 0 --no-open
```

連接埠 `0` 交給系統分配，URL 從子程序 stdout 的 `dsh web: http://127.0.0.1:PORT/?token=…` 行解析。結束應用程式會終止該子程序（「中斷連線」按鈕也一樣）。30 秒內沒等到那一行就判定逾時並終止子程序，介面不會永遠停在「啟動中」。

**尋找 `dsh`**：從 Finder 雙擊啟動的應用程式繼承 launchd 的最小 PATH（`/usr/bin:/bin:/usr/sbin:/sbin`），裡面既沒有 node 也沒有 npm——而真機上幾乎每個 `dsh` 都是需要直譯器的包裝器（`#!/usr/bin/env node`、`npm exec …`、或 DSH Desktop 的執行時 shim）。所以「檔案存在且有 x 位」遠遠不足以稱為可用。搜尋按這個順序進行，每個候選都真用 `dsh --version` 跑一次，只有成功的才交給子程序：

1. Host 設定裡的「dsh 可執行檔路徑」
2. `BEZEL_DSH_PATH` 環境變數
3. 登入 shell 的 `command -v dsh`
4. 應用程式自身 PATH 上的 `dsh`
5. 常見安裝位置：`~/.local/bin`、`~/bin`、`/opt/homebrew/bin`、`/usr/local/bin`、`~/.npm-global/bin`、`~/.bun/bin`、`/opt/anaconda3/bin`、……

第 3 步問的是**互動式**登入 shell（`zsh -l -i -c`，失敗退到 `-l -c`）：放著 `node`/`npm` 的目錄通常寫在 `~/.zshrc` 裡，非互動的 `zsh -l -c` 永遠不讀它——這正是 GUI 應用程式的 PATH 和使用者終端機對不上的原因。探測用一行哨兵把 rc 檔案的雜訊和答案分開，逾時 5 秒。

子程序的 PATH 是：登入 shell 的 PATH → 應用程式繼承的 PATH → 直譯器目錄，去重合併。注意只注入**直譯器目錄**——絕不注入像 `~/bin`、`~/.local/bin` 這種可能住著*另一個* `dsh` 的目錄：有些包裝器自己會掃 PATH 並聽命於找到的東西（DSH Desktop 的 shim 就這樣），把另一個包裝器放上 PATH 等於把啟動交給它，而不是用 shim 自帶的執行時。

所有候選都失敗時，連線提示會列出試過的每個位置和失敗原因（不存在，或 `--version` 跑不起來）。

**憑證語義**：`GET /?token=…` 由 Host 換成一張簽署 Cookie，30 天有效（`dsh-auth-<hash(authority)>`，`HttpOnly`）。簽署金鑰持久化在 Host 的憑證裡，所以 Cookie 活得過 Host 重新啟動；沒有 Cookie 時才需要 token。Cookie 有效時，Host 的首頁授權把任何 `?token=` 請求 303 重定向到乾淨的 `/`，所以把 token 留在位址裡是安全的——而且只要 Cookie 還在，過期的 token 也不會變成 401。兩個都不行時，頁面會明說。

**多個 Host**：Cookie 名裡帶授權方雜湊，幾個 Host 的對話在同一個 WebKit 資料儲存裡並存；切換 Host 不過是切換 URL。

## 設定

設定視窗（工具列 Host 選單 →「管理 Host…」，或 ⌘,）有兩個標籤頁。

**Host**——增刪改書籤：

| 欄位 | 含義 |
| --- | --- |
| 名稱 | 顯示在選擇器裡；留空則用位址 |
| 位址 | Host 的 origin，例如 `http://127.0.0.1:3080` |
| 啟動 token | `dsh web` 輸出裡的 `?token=…`；僅在沒有 Cookie 時需要 |
| 由本應用程式啟動本機 dsh | 本應用程式產生子程序 |
| profile | 代管模式的 `--profile`，預設 `web` |
| 額外參數 | 追加到 `dsh` 呼叫後，例如 `--trusted-host dsh.internal` |
| 自訂啟動命令 | 代管模式下整體替換呼叫；必須列印 `dsh web: http://…` 行 |
| dsh 可執行檔路徑 | 代管模式執行哪個 `dsh`；留空表示搜尋（見「尋找 `dsh`」） |

**一般**——屬於應用程式而非某個 Host 的偏好：

| 欄位 | 含義 |
| --- | --- |
| 語言 | 介面語言：英語（預設）、簡體中文、繁體中文、日本語、Français、Deutsch 或 Español |
| 通知 | 等待中的 Host 與結束的任務的 macOS 通知；預設開啟 |
| 設定檔 | 設定存於何處；顯示路徑，選取可以拷貝 |

書籤與其餘設定隨編輯寫入那個檔案；寫入、遷移與保護的方式見上面的「記住了什麼」。

## 布局

```
Sources/BezelCore/          連線與訊號模型（無 SwiftUI，可單測）
  DSHHost.swift             Host 書籤：origin 歸一化、token→URL、參數拆分
  AppConfig.swift           兩次啟動之間記住的一切，作為一個值
  ConfigFile.swift          JSON 檔案：位置、原子寫入、寬容讀取
  ConfigStore.swift         這個值的唯一持有者：載入、編輯、持久化
  Localization.swift        七種語言，以及每則訊息的全部譯法
  DSHDiscovery.swift        尋找可用的 dsh：登入 shell 探測、PATH 合併、候選、可執行性
  LocalHostRunner.swift     代管子程序：非同步發現、啟動行解析、逾時、結束診斷
  DSHProcessScan.swift      掃描程序找執行中的 DSH（引導的偵測步驟）
  DSHInstall.swift          經 npm 安裝 dsh（引導的自動路徑）
  PageSignals.swift         頁面快照、觀察/探測指令碼、事件檢測器
  ShellCommand.swift        帶逾時的一次性 shell 呼叫
  BoundedProcess.swift      輸出有界、事後可讀的子程序
  OneShotCommand.swift      小的程序執行輔助
  JSONValue.swift           設定經它解碼的寬容 JSON 樹
Sources/dsh-bezel/          應用程式與 UI
  BezelApp.swift            入口、語言鏡射、--dump-config / --dump-hosts 冒煙入口
  Model/AppState.swift      設定/子程序/WebView/探測頁的黏合，連線狀態，通知措辭
  Model/Notifier.swift      macOS 通知投遞與兩條投遞規則
  Web/WebView.swift         WKWebView 宿主、導覽狀態回報、觀察指令碼的通道
  Web/SidebarProbe.swift    讀取完整側欄的隱藏頁面
  UI/MainView.swift         工具列、Host 選擇器、連線提示、錯誤橫幅
  UI/OnboardingView.swift   首次啟動引導
  UI/SettingsView.swift     Host 管理與應用程式偏好（兩個標籤頁）
Tests/BezelCoreTests/       位址歸一化、啟動行解析、設定檔與儲存、在地化、頁面訊號
```

## 已知限制

- **純 http 與 ATS**：Host 可能是區域網路裡的 `http://`，所以 `Resources/Info.plist` 設了 `NSAllowsArbitraryLoadsInWebContent`（只放寬 WebView 內容；應用程式自身的請求仍在 ATS 之下）。前置一個 `https://` 反向代理就不需要它了。
- **遠端 Host 得接納這個用戶端**：dsh 的 `/api` 有一道瀏覽器信任欄，接受回環、部署推得的區域網路 IP 字面值、或經 `--trusted-host` 宣告的授權方。要用網域名稱連遠端 Host，那個 Host 必須帶 `--trusted-host` 啟動。另注意 `dsh web` 的 CLI 拒絕 `--host 0.0.0.0`；要服務到本機之外得在設定層寫 `host: '0.0.0.0'`。
- **無 App Sandbox**：代管模式要產生 `dsh`，而 harness 的對話工具本來就在使用者機器上跑命令，沙箱會破壞那個信任模型。只連外部 Host 的話可以自己加沙箱和 `com.apple.security.network.client`。
- **範圍**：本應用程式不給對話本身添加任何功能——Web UI 有什麼就是什麼。它在顯示之外補的是 Host 選擇器、通知、語言和首次啟動引導。
- **前置條件**：一個能伺服 Web UI 的 dsh Host。`dsh web` 的啟動行與 `?token=` 兌換自 0.1.5-rc.1 起就是穩定的。

## 與 dsh-for-mac 的關係

`dsh-for-mac` 走另一條路：用 Swift 重實作線上協定（一元 RPC + `/api/remote.mux` + 事件串流），換來完全原生的互動，代價是自己追蹤協定、自己扛漂移。本專案刻意不這麼做。兩者可以並存；本應用程式確實補的原生形狀的東西——通知、跟隨語言的選單列——都包在頁面外面，不碰連線模型。

## 開發

```sh
swift build --disable-sandbox
swift test --disable-sandbox
swift run dsh-bezel --dump-config   # 設定檔：路徑，或它裝著什麼
swift run dsh-bezel --dump-hosts    # 只看儲存的書籤
```

裸可執行檔和 bundle 共用一個設定檔，所以 `swift run` 做實驗用的就是真實設定——除非 `BEZEL_CONFIG` 另有指向。在 DSH harness 下建置需要 `--disable-sandbox`，因為它嵌不進自己的沙箱。
