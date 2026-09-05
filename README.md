# Diurna

Diurna 是一个使用 Flutter 和 Supabase 构建的个人信息管理应用，包含收集箱、日程、日记和备忘录功能。

当前主要使用平台是 Windows、iOS 和 Web。仓库保留 Flutter 生成的其他平台工程，以便未来扩展。

## 功能

- 收集箱：快速收集、分类、置顶、归档和拖拽整理信息。
- 日程：按日期管理待办事项。
- 日记：按日期记录正文、心情和标签。
- 备忘录：纯文本标题与正文、手动保存和跨设备拖拽排序。Windows
  首页将它放在左侧日程下方；Web 宽屏使用左右分栏，手机浏览器使用列表与详情页。
- 机器接口：共享 Dart 业务层、独立 Windows JSON CLI、20 个 stdio MCP tools 和 Diurna Skill。
- 同步协议 v2：版本冲突保护、持久化上传回执、Realtime 通知及冲突处理。

## 本地运行

1. 复制 `.env.example` 为 `.env`，填写 Supabase 配置。
2. 在 Supabase SQL Editor 中执行 `supabase/schema.sql` 初始化新项目。
3. 现有项目先备份并按 [同步升级说明](docs/sync-protocol.md) 执行增量迁移。
   不要在已有用户数据上重跑 20260711 的测试数据重建脚本。
4. 远端必须支持 protocol v2；启用协议门槛后旧客户端需要升级才能继续上传。
5. 获取依赖并运行应用：

```sh
flutter pub get
flutter run -d windows
```

Windows Release 客户端在 `build/windows/x64/runner/Release/diurna.exe`，需连同同目录的 `data` 和 dll 一起使用。协议 v2 启用后，旧客户端无法继续上传。

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
