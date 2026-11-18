# 怎么拿到一个能装上手机的安装包

## 先说死结论

**在这台 Windows 上产不出能装的 ipa。** 不是缺工具，是 Apple 的签名链只认它自己的东西：

- iOS 的 `.app` 必须用 **Apple 的 iOS SDK + clang** 编译（只有 macOS 有）
- 编出来还不够，**必须用你的 Apple ID 对应的证书签名**，否则手机报「未受信任」
- 证书只能通过 **Xcode** 或 **网页端开发者账号**生成，网页端那条要 $99/年

所以「一条命令出 ipa 直接装」不存在。但下面三条路都能通，按省事程度排。

---

## 路 A：GitHub Actions 云编译 + AltStore（**不用买 Mac，不用花钱**）

这条路是：GitHub 的免费 macOS runner 帮你编译，你的 Windows 负责签名安装。

### A1. 让 GitHub 帮你编

1. 注册 GitHub（免费）→ 新建仓库（Private 也行）
2. 把 `ios-agent/` 目录**里面的内容**作为仓库根目录推上去，结构应该是：

```
仓库根/
├── project.yml
├── AgentApp/
└── .github/workflows/build-ipa.yml     ← 已经给你写好了
```

3. 推上去后 → 仓库页面 **Actions** → 左边 **build-ipa** → **Run workflow**
4. 等 5–10 分钟 → 跑完在页面底部 **Artifacts** 下载 `PocketAgent-unsigned-ipa`
5. 解压得到 `PocketAgent-unsigned.ipa`

> 这个 workflow 干的事：`brew install xcodegen` → `xcodegen generate` → `xcodebuild archive`（关签名）→ 打包成 ipa → 传成 artifact。

### A2. 在 Windows 上签名装进手机

1. Windows 装 **AltServer**（[altstore.io](https://altstore.io)，Windows 版）
   - 新系统要先装 **Apple Devices**（微软商店）或 iTunes（非商店版），AltServer 依赖它的驱动
2. 手机装 **AltStore**（AltServer 通过数据线推过去）
3. 手机连同一个 Wi-Fi，AltServer 托盘图标 → Install AltStore → 选你的手机 → 输入 **Apple ID 和密码**（只用于向 Apple 换签名证书，不经过第三方服务器）
4. 把 `PocketAgent-unsigned.ipa` 传到手机（AirDrop/微信/文件 App 都行）→ 用 AltStore 打开它 → 它会自动重签并安装
5. iPhone 上：设置 → 通用 → VPN与设备管理 → 信任你的 Apple ID

**代价**：免费账号 7 天过期，AltStore 会在后台自动续签（需要手机和装 AltServer 的 Windows 在同一 Wi-Fi，每周至少连一次）。

---

## 路 B：付费开发者账号 + TestFlight（**最省心，$99/年**）

1. 加入 Apple Developer Program
2. 在 Apple Developer 网站创建 **App ID** + **分发证书** + **Provisioning Profile**（网页端就能做，不用 Mac）
3. 把这三样转成 GitHub Secrets，workflow 里加 `fastlane` 或 `xcodebuild -exportArchive` 出签名 ipa，再用 **App Store Connect API Key** 上传 TestFlight
4. 手机装 TestFlight → 邀请自己 → 90 天有效期，自动续

好处：**不用每周重签**，能装到任何自己的设备，也能给家人内测。
坏处：$99/年 + 配置繁琐（我可以把整段 workflow 和 fastlane 配置文件写好，你只要填三个 secret）。

---

## 路 C：借一台 Mac 用 30 分钟

`xcodegen generate` → 打开工程 → 选 Team → 连手机 → Run。
一条命令都不用背，代价是要有 Mac 或找朋友。免费账号同样 7 天。

---

## 路 D：不装包 —— 网页版加主屏（**已经能用**）

`ios-agent/web/index.html` 已经做好，图标也配好了（180/192/512 三档，Safari 会拿 `apple-touch-icon` 当主屏图标）：

1. Safari 打开部署地址
2. 分享 → **添加到主屏幕**
3. 桌面出现「小椒」图标，点开全屏、无地址栏、有图标

**跟真 App 的差别只有两处**：没有系统通知、抓网页受 CORS 限制（已做三级回退）。
好处：零签名、零过期、零审核、改代码即时生效。

> 要让它脱离这台电脑，把 `web/` 里四个文件（`index.html`、`manifest.webmanifest`、`icon-180/192/512.png`）扔到 GitHub Pages / Cloudflare Pages / Vercel，就是一个永久地址。全程免费，不需要服务器。

---

## 我的建议

| 你的情况 | 走哪条 |
|---|---|
| 就想现在有个东西用 | **D**，五分钟 |
| 想要真 App 图标 + 通知，不想花钱 | **A**（GitHub + AltStore） |
| 想一劳永逸、还要给家人用 | **B**（$99 + TestFlight） |
| 身边能借到 Mac | **C**，最快 |
