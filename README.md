# 回收统计 · 原生 iOS 版

把网页版（`736918.top`）按同样的界面与业务口径重写的 SwiftUI 原生 App，用 GitHub Actions 自动构建未签名 IPA，TrollStore 直接安装。

**为什么要有原生版：** 网页版被塞进 Capacitor 套壳后，`a.download` 不生效、相机权限拿不到、外链会顶掉整个 App、改了服务器 App 也看不到。原生版把这几块全部换成本系统能力。

---

## 一、怎么出 IPA（不需要 Mac）

1. 把这个目录的内容作为**仓库根**上传（`.github/workflows/ios.yml` 必须在根目录）。
2. push 任意提交 → Actions 里跑 `build-ipa`。
3. 构建完成后在 Artifacts 下载 `MeizhuangNative-ipa`，解压得到 `MeizhuangNative.ipa`。
4. TrollStore 打开 IPA 安装。

本地有 Mac 的话也可以：

```bash
brew install xcodegen
xcodegen generate
open MeizhuangNative.xcodeproj
```

---

## 二、工程结构

| 文件 | 职责 |
|---|---|
| `project.yml` | xcodegen 工程定义（iOS 16+、仅 iPhone、竖屏、相机/相册权限、ATS 允许备用 http） |
| `.github/workflows/ios.yml` | CI：xcodegen → xcodebuild → 打 Payload → 出 IPA |
| `Sources/MeizhuangApp.swift` | 入口、根视图、全局轻提示 |
| `Sources/Design.swift` | 设计令牌（与网页版 CSS 变量一一对应）+ 金额/时间格式化 |
| `Sources/Models.swift` | 运单、状态判定、结算三态、查价、照片模型 |
| `Sources/Parser.swift` | **一句话录入解析**（单号/金额/物品/上门客人名/子母件/变更单号/快递公司） |
| `Sources/API.swift` | 网络层、Keychain、主备线路、全部业务接口 |
| `Sources/AppState.swift` | 登录态、列表、缓存、统计、录入/结算/删除/批量查轨迹 |
| `Sources/LoginView.swift` | 账号密码登录 + 记住设备 |
| `Sources/HomeView.swift` | 首页：顶栏统计、搜索、列表、账号菜单、底部录入 |
| `Sources/ShipmentCardView.swift` | 运单卡片 |
| `Sources/ShipmentDetailView.swift` | 详情：轨迹、结算/部分结算/寄存、照片、删除 |
| `Sources/ComposeView.swift` | 一句话录入弹窗 |
| `Sources/ScanView.swift` | 原生相机扫码（AVFoundation）+ 相册条码识别（Vision） |
| `Sources/PriceView.swift` | 回收查价（多商家并排、调价记录、近 7 天变动） |
| `Sources/MergeView.swift` | 合并上门单 |
| `Sources/Export.swift` | CSV 导出 + 系统分享面板 |
| `Sources/Assets.xcassets` | App 图标 |

零第三方依赖，不需要 CocoaPods / SPM。

---

## 三、功能清单

### 第一批（浏览与查询）

- 账号密码登录；「记住这台设备」后换一把 90 天设备密钥，之后免密进
- 首屏列表 + 本机缓存秒开（弱网不再空白干等）
- 下拉刷新、关键词搜索
- 顶栏统计：7 天未结算、今日单量（快递/上门拆分）、在途与异常
- 运单卡片：等宽单号、状态徽章、物品清单、快递/客人、金额、轨迹条数
- 点卡片看完整物流轨迹

### 第二批（作业功能）

- **一句话录入**：`单号 物品 金额` 直接提交；上门单写 `上门 客人名 物品 金额`；金额优先认「元/块/¥」，没有标记时取最后一个独立数字（不会再把「100ml」当价格）
- **变更单号**：`运单号：旧号，变更，运单号：新号`，改原记录并把旧号累积进「原单号」
- **扫码录入**：相机实时识别 code128 等一维码 + 相册图片识别，识别到自动带回录入框
- **结算**：填结算金额自动标记已结算、自动把柜/驿站件转已签收；清空金额即回退
- **部分结算 / 寄存**：标了寄存且结回的钱少于货值 → 按「部分结算」算，仍进未结清单，利润暂不计（与网页版三态口径一致）
- **回收查价**：搜索后同一款按商家并排显示（吉尼优先），红字「昨出货」标；点进去看逐次调价记录；近 7 天涨跌榜（涨红跌绿）
- **合并上门单**：多选上门单 + 填快递单号 → 后端事务里建新单删原单，原单号留痕
- **导出 CSV**：系统分享面板，可存「文件」App 或发微信
- **照片上传**：相册选图自动压到 1600px/0.72 再传（避开后端 8MB 上限），按运单号归集
- **一键查询轨迹**：串行查询未签收的单，结果回写运单

---

## 四、和网页版的口径对齐（改动前务必先看）

1. **结算三态**：`settled` 只代表「动过结算」。判定部分结算是 `settled && deposit && 结算额 < 货值`。**必须带 deposit 标记**——没标寄存但结算额不足的是讲价结亏，算已结算（利润为负），不能算未结。
2. **未结余额**：没结过=全额；部分结算=差额。
3. **利润**：只有结清的单才算利润，部分结算返回 0，否则「结一半」会显示成假亏损。
4. **上门单**：`自取/上门/自提/送货上门/当面…` 统一存成「上门回收」，重号自动加 2、3…；客人名存在 `carrier_name`。
5. **查价**：主价是散户价，`price2` 是代理价；`hot=1` 表示该价在金山文档里是红字（昨天出过货）。
6. **涨跌配色**：涨=红、跌=绿（国内习惯，和欧美相反）。

---

## 五、TrollStore 相关

- 伪签名安装没有正式 entitlements，**Keychain 可能返回 -34018**。`Keychain.set/get` 做了双写：Keychain 成功就用它，失败自动回退 `UserDefaults`（`kc_` 前缀），不会出现「装完一直要求登录」。
- 相机/相册权限走系统弹窗，首次使用会问；拒绝了可以在系统设置里再打开。
- TrollStore 支持范围大致到 iOS 17.0（部分版本 16.6.1），换设备前先确认。
- 未签名 IPA 不能上架 App Store，也不要拿去做企业分发。

---

## 六、已知限制

- **主备线路**：主 `https://736918.top`，备 `http://8.134.91.157`。只有网络层失败才降级，且一次会话只降一次；降级状态会记住，下次启动先试主线路。备用是明文 HTTP，token 会明文传输，仅作救急。
- **照片只进不出**：目前能上传和查看缩略图，没有做删除和原图浏览。
- **批量查轨迹较慢**：免费通道限速，每单之间留 0.9 秒，几十单要等一会儿。缺手机尾号的顺丰/中通会失败，失败数会提示。
- **没有做离线暂存**：网页版有「断网先存、联网补交」，原生这版没做，断网提交会直接报错。

---

## 七、CI 报错怎么查

没有 Mac 时只能靠 CI 的日志。常见几类：

| 报错关键词 | 原因 | 处理 |
|---|---|---|
| `initializer is inaccessible due to 'private'` | SwiftUI struct 有 private 存储属性时，自动生成的 init 也是 private | 给该 View 补 `init() {}` 或显式 init（本工程已全部补齐） |
| `cannot find 'XXX' in scope` | 少文件 / 文件没进 target | 确认在 `Sources/` 下，`xcodegen generate` 会整目录扫描 |
| `use of unresolved identifier 'MZ'` | `Design.swift` 没编进去 | 同上 |
| `Cannot use instance member ... within property initializer` | 在属性默认值里用了别的属性 | 挪进 `init` 或 `.onAppear` |
| `Signing for "MeizhuangNative" requires a development team` | 签名没关干净 | 确认 `CODE_SIGNING_ALLOWED=NO`（workflow 里已带） |
| `Assets.xcassets` 图标告警 | 图标尺寸不对 | `AppIcon.appiconset` 里 1024×1024 单尺寸即可 |

把 Actions 里失败那一步的日志贴出来即可，按行改。
