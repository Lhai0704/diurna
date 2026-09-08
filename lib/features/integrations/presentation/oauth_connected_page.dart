import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OauthConnectedPage extends StatelessWidget {
  const OauthConnectedPage({this.provider, this.error, super.key});

  final String? provider;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final failed = error != null && error!.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('外部连接')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  failed ? Icons.error_outline : Icons.check_circle_outline,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  failed ? '连接未完成' : '已连接，可以关闭此页面。',
                  textAlign: TextAlign.center,
                ),
                if (provider != null && !failed) ...[
                  const SizedBox(height: 8),
                  Text(provider!),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go('/settings/integrations'),
                  child: const Text('返回外部连接'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
