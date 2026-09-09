import 'dart:async';

import 'package:diurna/app/visual_style.dart';
import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:diurna/features/auth/presentation/login_page.dart';
import 'package:diurna/features/auth/presentation/register_page.dart';
import 'package:diurna/features/calendar/presentation/calendar_page.dart';
import 'package:diurna/features/diary/presentation/diary_list_page.dart';
import 'package:diurna/features/home/presentation/windows_home_page.dart';
import 'package:diurna/features/inbox/presentation/inbox_page.dart';
import 'package:diurna/features/integrations/presentation/external_conflicts_page.dart';
import 'package:diurna/features/integrations/presentation/integrations_page.dart';
import 'package:diurna/features/integrations/presentation/oauth_connected_page.dart';
import 'package:diurna/features/memo/presentation/memo_page.dart';
import 'package:diurna/features/settings/presentation/settings_page.dart';
import 'package:diurna/features/settings/providers/visual_style_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);

  return GoRouter(
    initialLocation: '/inbox',
    refreshListenable: GoRouterRefreshStream(authRepository.authStateChanges),
    redirect: (context, state) {
      final loggedIn = authRepository.currentUser != null;
      final authRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      if (!loggedIn && !authRoute) {
        return '/login';
      }
      if (loggedIn && authRoute) {
        return '/inbox';
      }
      final memosRoute = state.matchedLocation.startsWith('/memos');
      final unsupportedNativeMemoRoute =
          !kIsWeb && defaultTargetPlatform != TargetPlatform.windows;
      if (loggedIn && memosRoute && unsupportedNativeMemoRoute) {
        return '/inbox';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
        routes: [
          GoRoute(
            path: 'integrations',
            builder: (context, state) => const IntegrationsPage(),
            routes: [
              GoRoute(
                path: 'conflicts',
                builder: (context, state) => ExternalConflictsPage(
                  connectionId: state.uri.queryParameters['connectionId'],
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/integrations/connected',
        builder: (context, state) => OauthConnectedPage(
          provider: state.uri.queryParameters['provider'],
          error: state.uri.queryParameters['error'],
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/inbox',
                builder: (context, state) => const InboxPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (context, state) => const CalendarPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/diary',
                builder: (context, state) => const DiaryListPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/memos',
                builder: (context, state) => const MemoPage(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (context, state) => const MemoDetailPage(),
                  ),
                  GoRoute(
                    path: ':memoId',
                    builder: (context, state) =>
                        MemoDetailPage(memoId: state.pathParameters['memoId']),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class HomeShell extends ConsumerWidget {
  const HomeShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visualStyle = ref.watch(visualStyleProvider);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    if (shouldUseDesktopLayout(style: visualStyle, wide: wide)) {
      return const WindowsHomePage();
    }

    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.inbox_outlined),
        label: '收集箱',
      ),
      const NavigationDestination(
        icon: Icon(Icons.event_note_outlined),
        label: '日程',
      ),
      const NavigationDestination(icon: Icon(Icons.book_outlined), label: '日记'),
      if (showMemoNavigation)
        const NavigationDestination(
          icon: Icon(Icons.note_outlined),
          label: '备忘录',
        ),
    ];

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: navigationShell.goBranch,
              labelType: NavigationRailLabelType.all,
              destinations: [
                const NavigationRailDestination(
                  icon: Icon(Icons.inbox_outlined),
                  label: Text('收集箱'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.event_note_outlined),
                  label: Text('日程'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.book_outlined),
                  label: Text('日记'),
                ),
                if (showMemoNavigation)
                  const NavigationRailDestination(
                    icon: Icon(Icons.note_outlined),
                    label: Text('备忘录'),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: navigationShell.goBranch,
        destinations: destinations,
      ),
    );
  }
}
