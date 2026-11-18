# 巨魔商店（TrollStore）路线

## 结论

**能装，而且是对我们这种自用 App 最理想的方式**：永久签名、不用 Apple ID、不会 7 天掉签、不需要 $99。

但它只解决"签名"，不解决"编译"——ipa 还是得先编出来（GitHub Actions，免费，见 [PACKAGING.md](PACKAGING.md)）。

---

## 前提 1：iOS 版本（硬门槛）

以 The Apple Wiki 与 opa334 官方仓库为准（TrollStore 最新 2.1.1，2026-04-01）：

| iOS | 支持 | 装 TrollStore 用什么 |
|---|---|---|
| 14.0 – 16.6.1 | ✅ | TrollInstallerX（需先侧载一次） |
| 16.7 RC (20H18) | ✅ | TrollInstallerX |
| 17.0 | ✅ | TrollRestore（需要电脑，Windows 版有） |
| 17.1 – 17.5 | ❌ | 无解 |
| 17.6 / 18 / 26.x | ❌ | 苹果补了洞：非 root 进程不能 fork root 进程，CoreTrust 绕过也没用 |

查版本：设置 → 通用 → 关于本机 → 软件版本。

> 换句话说：**手机版本越新，这条路越堵**。反而是留在 16.6.1 的老机器最香。

---

## 前提 2：一个 ipa

用 [build-ipa.yml](.github/workflows/build-ipa.yml) 在 GitHub 上编，产出两个文件：

| 文件 | 给谁用 |
|---|---|
| `PocketAgent.tipa` | **TrollStore**（已 ad-hoc 签名，点开即装） |
| `PocketAgent-unsigned.ipa` | AltStore / SideStore（7 天续签） |

---

## 装到手机：三步

1. 把 `PocketAgent.tipa` 传到手机（AirDrop / 微信 / 文件 App / 或者直接给个 URL 在 TrollStore 里粘）
2. 用 **TrollStore** 打开它 → 弹出安装确认 → 装
3. 回桌面，图标在那儿，点开就能用

**没有第 4 步。** 不用信任证书、不用连电脑、不会过期。

---

## TrollStore 能给我们多出来的东西

| 能力 | 普通签名 | TrollStore |
|---|---|---|
| 永久有效 | ❌ 7 天 | ✅ |
| 需要 Apple ID | ✅ 必须 | ❌ 不需要 |
| 任意 entitlements | ❌ | ✅ |
| `get-task-allow`（可调试 + 可开 JIT） | ❌ | ✅ |
| 通知权限 | ✅ | ✅（1.0.5 起修复） |
| App Extension（分享扩展等） | ✅ | ⚠️ 部分支持 |

那条 **JIT** 值得记一下：将来如果想在 App 里塞个 JS 引擎（QuickJS）或 WASM 干重活，普通签名下 iOS 不给 JIT，TrollStore 版可以——性能差好几倍。

---

## 一个必须纠正的误解

**TrollStore ≠ 越狱。**

装了 TrollStore，App 仍然在 iOS 沙箱里：读写不了别人的目录、起不了子进程、没有 root。所以：

- ✅ 装 PocketAgent（纯原生 UI + 网络）—— 完美
- ❌ 装 dsh 的 Host（要 fork/exec 跑 pwsh/bash）—— **照样不行**

想跑 dsh 本体，还是只有"整机模拟（UTM SE）"或"真越狱"两条路。TrollStore 帮不了这一块。

---

## 如果版本对不上怎么办

| 情况 | 走哪条 |
|---|---|
| iOS ≤ 16.6.1 / 17.0 | TrollStore + `PocketAgent.tipa`，最省心 |
| iOS 17.1+ | AltStore（7 天续签）或 TestFlight（$99） |
| 都不想折腾 | 网页版加主屏，零安装，已经能用 |
