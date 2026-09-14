# Diurna

Diurna 是一个使用 Flutter 和 Supabase 构建的个人信息管理应用，包含收集箱、日程、日记和备忘录功能。

当前主要使用平台是 Windows、iOS 和 Web。仓库保留 Flutter 生成的其他平台工程，以便未来扩展。

## 功能

- 收集箱：快速收集、分类、置顶、归档和拖拽整理信息。
- 日程：按日期管理待办事项。
- 日记：按日期记录正文、心情和标签。
- 备忘录：纯文本标题与正文、手动保存和跨设备拖拽排序。复古/现代四宫格把它放在左侧日程下方；Web 风格宽屏使用左右分栏，手机浏览器使用列表与详情页。
- 机器接口：共享 Dart 业务层、独立 Windows JSON CLI、20 个 stdio MCP tools 和 Diurna Skill。
- 同步协议 v2：版本冲突保护、持久化上传回执、Realtime 通知及冲突处理。
- 外部连接：单向把 Inbox / Memo / Diary 导出到 Notion，把全日程事件导出到 Google Calendar。云端 generation 变化并稳定约 1 分钟后自动导出，也可在 **外部连接** 页立即同步。支持在 Diurna 管理的 Notion 数据源 / Google 日历中新建对象并自动建立双向 link（Google 限单日非重复全天事件，Notion 正文限无损支持内容）；已关联条目继续通过 webhook + worker 反向入站；打开冲突在 **查看冲突** 中显式选择 **使用 Diurna** 或 **使用外部**。从 **设置** 进入：四宫格桌面在日记面板标题栏，Web 风格在收集箱顶栏。授权、导出与冲突解决走 Edge Functions，Flutter 不读取第三方 token。详见 [外部连接](docs/external-integrations.md) 和 [双向同步](docs/external-bidirectional-sync.md)。
- 主题：设置中可切换 **复古**、**现代风格**（同一套四宫格，配色与边框不同）和 **Web 风格**（分页导航）。Windows 默认复古，Web 与 iOS 默认 Web 风格。

## 本地运行

1. 复制 `.env.example` 为 `.env`，填写 Supabase 配置。
2. 在 Supabase SQL Editor 中执行 `supabase/schema.sql` 初始化新项目。
3. 现有项目先备份并按 [同步升级说明](docs/sync-protocol.md) 执行增量迁移。
   不要在已有用户数据上重跑 `20260711000001` / `20260711000002` 的测试数据重建脚本。
4. 远端必须支持 protocol v2；启用协议门槛后旧客户端需要升级才能继续上传。
5. 获取依赖并运行应用：

```sh
flutter pub get
flutter run -d windows
```

Windows Release 客户端在 `build/windows/x64/runner/Release/diurna.exe`，需连同同目录的 `data` 和 dll 一起使用。协议 v2 启用后，旧客户端无法继续上传。

外部连接的 OAuth 密钥、`INTEGRATION_TOKEN_KEY`、`SUPABASE_DB_URL` 和入站用的 `INTEGRATIONS_MAINTENANCE_SECRET` 只放在 Supabase Edge Function Secrets，不要写入 `.env` 或仓库。Redirect URI、密钥名称、入站迁移顺序与回滚见 [外部连接](docs/external-integrations.md) 和 [双向同步](docs/external-bidirectional-sync.md)。已应用到托管库的 migration 不可再改，只能追加新的 additive migration。

## 数据与同步

- 本地数据使用 Drift 存储。
- 收集箱、日程、日记和备忘录通过 Supabase 在设备间同步。
- Supabase 表启用 RLS，每个用户只能访问自己的数据。
- Flutter 和 CLI 使用独立本地库，通过 Supabase 同步；不共享数据库文件或 session。
- 上传失败保留本地队列，并发冲突不会静默覆盖。Realtime 只触发同步，不直接应用事件正文。

## CLI / MCP

在 `packages/diurna_cli` 执行 `dart pub get` 和
`dart build cli -o build --target bin/diurna.dart`。
产物为 `build/bundle/bin/diurna.exe`，需连同 `bundle/lib` 一起使用。

登录、JSON 契约、MCP 配置和示例见 [机器接口文档](docs/machine-interface.md)。
Agent 操作指引在 [Diurna Skill](skills/diurna/SKILL.md)，开发指引在 [AGENTS.md](AGENTS.md)。

## 验证

```sh
cd packages/diurna_core
dart pub get
dart run build_runner build
dart analyze
dart test
cd ../diurna_cli
dart pub get
dart analyze
dart build cli -o build --target bin/diurna.dart
dart test
cd ../../mcp
npm ci
npm run typecheck
npm test
npm run build
cd ..
flutter pub get
flutter analyze
flutter test
flutter build windows --release
flutter build web --release --dart-define-from-file=.env
```

推送到 `main` 后，GitHub Actions 会执行分析、测试、Web 构建并部署到
Cloudflare Pages。

验证结果及未完成的真实环境验收见 [implementation-status](docs/implementation-status.md)。
