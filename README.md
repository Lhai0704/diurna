# Diurna

Diurna 是一个使用 Flutter 和 Supabase 构建的个人信息管理应用，包含收集箱、日程、日记和备忘录功能。

当前主要使用平台是 Windows、iOS 和 Web。仓库保留 Flutter 生成的其他平台工程，以便未来扩展。

## 功能

- 收集箱：快速收集、分类、置顶、归档和拖拽整理信息。
- 日程：按日期管理待办事项。
- 日记：按日期记录正文、心情和标签。
- 备忘录：纯文本标题与正文、手动保存和跨设备拖拽排序。Windows
  首页将它放在左侧日程下方；Web 宽屏使用左右分栏，手机浏览器使用列表与详情页。

## 本地运行

1. 复制 `.env.example` 为 `.env`，填写 Supabase 配置。
2. 在 Supabase SQL Editor 中执行 `supabase/schema.sql` 初始化新项目。
3. 如果远端仍使用旧的 `tasks` 表，执行
   `supabase/migrations/20260711_rebuild_tasks_as_inbox_items.sql`。
4. 现有 Supabase 项目升级到备忘录版本时，先执行
   `supabase/migrations/20260904_add_memos.sql`。
5. 获取依赖并运行应用：

```sh
flutter pub get
flutter run -d windows
```

## 数据与同步

- 本地数据使用 Drift 存储。
- 收集箱、日程、日记和备忘录通过 Supabase 在设备间同步。
- Supabase 表启用 RLS，每个用户只能访问自己的数据。
- 发布包含备忘录的客户端前必须先执行备忘录迁移，否则整轮远端快照同步会失败；
  离线写入仍会保留在本地同步队列中等待重试。

## 验证

```sh
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter build windows
flutter build web --release --dart-define-from-file=.env
```

推送到 `main` 后，GitHub Actions 会执行分析、测试、Web 构建并部署到
Cloudflare Pages。
