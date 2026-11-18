# PocketAgent —— 手机里独立的 agent

一个**不需要电脑、不需要服务器、不需要 Node、不需要 fork/exec** 的 iOS agent。
整个 agent 循环跑在手机上，只有推理请求发出去。

```
你说话 → 模型返回 tool_calls → App 执行原生工具 → 结果回灌 → 再问模型 → 出答案
```

**为什么这算"独立"**：agent 的能力 = 循环 + 手。循环是纯逻辑；"手"换成 iOS 原生能力（文件、剪贴板、通知、提醒事项、HTTP、打开链接），就不再需要子进程——而子进程正是 iOS 唯一给不了的东西。

---

## 一、装到手机上（三条路，都不需要买开发者账号）

### 路 1：Xcode（有 Mac，最省事）
```bash
brew install xcodegen
cd ios-agent
xcodegen generate
open PocketAgent.xcodeproj
```
选自己的 Apple ID 作为 Team → 连手机 → Run。
免费账号的签名 **7 天过期**，到期在 Xcode 里再 Run 一次即可（数据不丢）。

### 路 2：Swift Playgrounds（**没有 Mac 也能上真机**）
iPad / iPhone 上的 **Swift Playgrounds**（App Store 免费）能直接打开 App 工程并在本机运行：

1. 把 `AgentApp/` 里的 `.swift` 文件和 `Info.plist` 拷进「文件」App
2. Playgrounds → 新建 App → 把文件拖进左侧
3. 点 ▶ 运行

缺点：多文件工程在 Playgrounds 里管理麻烦，且它对 `Info.plist` 权限项支持有限（提醒事项权限可能拿不到，其余工具照常）。想省事还是借一台 Mac 跑路 1。

### 路 3：TestFlight（想做长期自用/给别人）
付费账号 $99/年 → Archive → App Store Connect → TestFlight 内测，90 天一轮，不用每周重签。

---

## 二、第一次打开

1. 右上角 `⋯` → **设置**
2. 填三样：
   - `baseURL`：`https://api.deepseek.com`（任何 OpenAI 兼容网关都行，比如 `https://api.openai.com/v1`）
   - `model`：`deepseek-chat`
   - `apiKey`：`sk-…`（存在 Keychain，不进明文存储）
3. 点 **测试连接**，看到「✅ 通了」就成了。

---

## 三、它现在的手（10 个工具，全部原生）

| 工具 | 干什么 | 需要权限 |
|---|---|---|
| `now` | 当前时间 / 时区 | — |
| `list_files` | 列沙盒目录 | — |
| `read_file` | 读文本文件 | — |
| `write_file` | 写文本文件（自动建目录） | — |
| `http_get` | 抓网页 / 调公开 API | — |
| `clipboard_get` / `clipboard_set` | 读/写系统剪贴板 | — |
| `open_url` | 交给系统打开链接或 App | — |
| `notify` | 发本地通知 | 通知权限 |
| `add_reminder` | 写进系统「提醒事项」 | 提醒事项权限 |

试试这几句，能立刻看出它不是普通聊天框：

- 「现在几点，帮我算距离今晚 23:00 还有多久」→ 会调 `now`
- 「抓 https://example.com 的标题存成 note.md，然后读回来念给我」→ 会连续调 `http_get` → `write_file` → `read_file`
- 「把刚才的结论放进剪贴板」→ `clipboard_set`，你切到微信直接粘
- 「提醒我明天交房租」→ 真的出现在系统提醒事项里

---

## 四、加一个工具（3 步，不用改别处）

以「查天气」为例：

1. **声明**（`Tools.swift` 的 `specs` 里加一条）
```swift
ToolSpec(name: "weather",
         description: "查询某城市当前天气。",
         parameters: obj(["city": str("城市名")], required: ["city"])),
```

2. **实现**（同一个文件 `run(name:argumentsJSON:)` 的 switch 里加一个 case）
```swift
case "weather":
    let city = args["city"] as? String ?? "北京"
    let (data, _) = try await URLSession.shared.data(from: URL(string: "https://wttr.in/\(city)?format=j1")!)
    return (String(data: data, encoding: .utf8) ?? "", false)
```

3. 跑起来 —— 模型自己会挑这个工具，不用告诉它。

想加**真正手机专属**的能力，都走同一个套路：HealthKit（步数/睡眠）、EventKit（日历）、Contacts、Photos、CoreLocation（定位）、Speech（语音转写）、Shortcuts（把活派给别的 App）。

---

## 五、和 dsh 比，丢了什么、留下什么

| | dsh（桌面/云端 Host） | PocketAgent（本机） |
|---|---|---|
| shell / 终端 / 跑代码 | ✅ | ❌（iOS 给不了，见下） |
| 读写任意路径 | ✅ | 只有 App 沙盒 |
| 装第三方插件/skill | ✅ 生态 | ❌ 要自己写进代码 |
| 手机系统能力（通知/提醒/剪贴板/健康） | ❌ 够不着 | ✅ 原生 |
| 要不要开电脑 / 有服务器 | 要 | **都不要** |
| 锁屏后长任务 | 一直跑 | 十几秒到几分钟（`beginBackgroundTask` 的上限） |

**关于"跑代码"**：iOS 上没有 fork/exec，这是平台事实。想要，只有三条缝：`ios_system`（把命令编成 dylib 链进 App）、WASM 解释器（wasm3）、或者整机模拟（UTM）。都不在"一个 agent App"的范围里。

---

## 六、下一步能加什么（按性价比）

1. **语音输入**：`SFSpeechRecognizer` + 长按说话，通勤时最有用
2. **分享扩展**：Safari 里看到东西 → 分享给 agent → 它读正文再答
3. **快捷指令 action**：让「嘿 Siri，问小椒」直接进 App
4. **子 agent**：在工具里再起一个 `AgentRuntime` 跑子任务，`subagent` 那味就出来了
5. **本地记忆**：把 `sessions.json` 里的事实抽成 `memories.json`，每次塞进系统提示词
6. **Widget**：主屏显示「上次说到哪」+ 一键继续

---

## 七、文件清单

```
ios-agent/
├── project.yml                 # XcodeGen 工程定义
├── AgentApp/
│   ├── PocketAgentApp.swift    # @main
│   ├── Models.swift            # 消息 / 工具规格 / 设置
│   ├── LLMClient.swift         # OpenAI 兼容，SSE 流式 + tool_calls 聚合
│   ├── AgentLoop.swift         # agent 主循环（轮数、取消、后台续命、持久化）
│   ├── Tools.swift             # 10 个原生工具 + 路径越界防护
│   ├── Store.swift             # 会话 JSON + 设置 + Keychain
│   ├── ChatView.swift          # 聊天 UI（气泡 / 工具卡片 / 流式）
│   ├── SettingsView.swift      # 设置 / 测试连接 / 会话列表
│   └── Info.plist              # 权限声明 + 后台模式
└── README.md
```

> 代码是按 iOS 16+ / Swift 5.9 写的，没有引入任何第三方依赖。第一次编译如果有报错，八成是 Xcode 版本差异（比如 `onChange` 的两参形式），把报错贴给我，我改。
