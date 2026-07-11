# Diurna

Diurna 是一个使用 Flutter 和 Supabase 构建的个人信息管理应用，包含收集箱、日程和日记功能。

当前主要使用平台是 Windows 和 iOS。仓库保留 Flutter 生成的其他平台工程，以便未来扩展。

## 本地运行

1. 复制 `.env.example` 为 `.env`，填写 Supabase 配置。
2. 在 Supabase SQL Editor 中执行 `supabase/schema.sql` 初始化新项目。
3. 如果远端仍使用旧的 `tasks` 表，执行
   `supabase/migrations/20260711_rebuild_tasks_as_inbox_items.sql`。
4. 获取依赖并运行应用：

```sh
flutter pub get
flutter run -d windows
```

## 数据与同步

- 本地数据使用 Drift 存储。
- 收集箱、日程和日记通过 Supabase 在设备间同步。
- Supabase 表启用 RLS，每个用户只能访问自己的数据。

## 验证

```sh
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter build windows
```
