# 打卡

一款原生 macOS 打卡/习惯追踪应用。SwiftUI + SwiftData 构建，核心逻辑全部下沉到纯函数层，可完整单测。

## 下载安装

从 [Releases](../../releases) 页面下载 `CheckinApp.dmg`，打开后把 **CheckinApp** 拖入「应用程序」文件夹即可。通用二进制，Apple Silicon 与 Intel Mac 均可运行，要求 **macOS 26.0+**。

**首次打开**：应用目前未做开发者签名与公证，首次启动时 macOS 可能提示「无法验证开发者」。处理方式：

- 打开 **系统设置 → 隐私与安全性**，在页面底部找到被拦截的提示，点 **仍要打开**；
- 或在终端执行一次：

  ```bash
  xattr -cr /Applications/CheckinApp.app
  ```

## 功能

- **今日**：每日任务、当天到期的指定日任务一键打卡；周期任务（每周/每月 N 次）进度卡
- **日历**：按周/月网格查看任务分布；今天与历史日可打卡/判定（补记），未来日只读
- **周期**：每日 / 每周 / 每月 / 每周某天四类任务的定义管理（编辑表单）
- **统计**：本周完成率与过关率、哪些任务总在漏、一周里哪天最容易崩、近四周趋势、连续达标周、每日任务连续天数
- **备份**：JSON 导出/导入（仅 Debug 构建可见），按 id 幂等还原，与数据库 schema 解耦

## 核心语义

这些口径是刻意设计并被测试锁定的，改动前请先读 `StatsUtil` 的文档注释：

- **打卡即完成**：点击「完成」即计入统计（`counted = true`），无论是否需要过关。「过关 / 没过关」只是质量标注，另设「过关率」单列；没过关同样算完成。
- **跳过 ≠ 完成**：跳过（单日豁免）写入 `counted = false` 的记录——单日级任务从应做槽位剔除；次数任务按「周期天数 − 跳过天数」封顶目标。连续天数跨过跳过日不断链。
- **补记合法，未来只读**：今天与历史日可打卡/判定/撤销（记录落到所选那天）；未来日打卡只读，但允许提前跳过（并能恢复）。
- **完成率永不超 100%**：应做与已做同源于 `(taskId, dateKey)` 槽位模型，并有 `done ≤ expected` 兜底。
- **达标线 80%**：连续达标周按「周完成率 ≥ 0.8」计；本周未打满不打断连续数，历史空周（应做为 0）跳过不断链。应做 < 3 次时统计页显示「样本不足」，绝不显示 0%。

### 状态机

| 动作 | 行为 |
|---|---|
| 完成 | 移除当天旧记录后写入新记录（同日重复覆盖）；需过关 → `awaiting`，否则 → `passed`；均 `counted = true` |
| 过关 / 没过关 | 当天 `awaiting` → `passed` / `failed`，均 `counted = true` |
| 撤销 | 删除当天记录（回到未完成；也是「恢复」取消跳过的逆向动作） |
| 跳过 | 删除当天记录后写入 `.skipped`（`counted = false`） |

周期任务（每周/每月）的记录携带 `periodKey`（周 `YYYY-Www` ISO，月 `YYYY-MM`），进度 = `min(次数目标, 周期天数 − 跳过天数)`；整周期被跳过 → `noExpectation`（无可做天数），达标 → `completed`，周期结束未达成 → `failed`，其余 → `inProgress`。

## 数据与持久化

- SwiftData 存储：`~/Library/Application Support/CheckinApp/checkin.store`（位置显式固定，可直接整目录备份；旧版 `default.store` 首次启动自动搬迁）。
- 版本化 schema v1 → v3，启动时轻量迁移（历史版本分别新增 `targetWeekday`、`endDate` 可选列），迁移失败不删库、直接报错指路。
- **备份建议用 JSON**（「备份」tab，仅 Debug 构建）：结构为 `{ "tasks": [...], "records": [...] }`，不绑定数据库版本，schema 变了也能导回；导入按 id 幂等 upsert，不删除现有数据。旧版数据中的 `"completed"` 状态导入时自动迁移为 `passed`。

## 构建与测试

```bash
open CheckinApp.xcodeproj        # Xcode 中 ⌘R 运行

# 命令行跑全部测试（54 个用例，含迁移/备份/状态机/统计口径）
xcodebuild test -project CheckinApp.xcodeproj -scheme CheckinApp -destination 'platform=macOS'

# 编译产物位置（已配置为跟随工程目录）
#   DerivedData/CheckinApp/Build/Products/Debug/CheckinApp.app
```

target 一览：`CheckinCore`（静态库）、`CheckinApp`（应用）、`CheckinCoreTests` + `CheckinAppTests`（单测，随 CheckinApp scheme 一并执行）。

## 已知限制

- UI 无跨天定时刷新：跨天后需一次界面更新才会派生新「今天」。
- `DateFormatter` 未固定 POSIX locale：系统日历设为非公历时字符串日期比较会错乱（中文环境默认公历，不受影响）。
- 任务详情页周期任务的「跳过今天」没有今日视图那道防呆，可在打卡后覆盖当天记录。
- 菜单栏常驻（MenuBar）为占位，尚未实现。
