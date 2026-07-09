import 'package:diurna/features/auth/data/auth_repository.dart';
import 'package:diurna/shared/widgets/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AuthForm extends ConsumerStatefulWidget {
  const AuthForm({required this.mode, super.key});

  final AuthFormMode mode;

  @override
  ConsumerState<AuthForm> createState() => _AuthFormState();
}

enum AuthFormMode { login, register }

class _AuthFormState extends ConsumerState<AuthForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final authRepository = ref.read(authRepositoryProvider);

    try {
      if (widget.mode == AuthFormMode.login) {
        await authRepository.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await authRepository.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        messenger.showSnackBar(
          const SnackBar(content: Text('注册已提交，请按 Supabase 邮件设置完成验证。')),
        );
      }
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authRepository = ref.watch(authRepositoryProvider);
    final isLogin = widget.mode == AuthFormMode.login;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isLogin ? '登录 Diurna' : '注册 Diurna',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  if (!authRepository.isConfigured) ...[
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          '请先填写项目根目录 .env：SUPABASE_URL 和 SUPABASE_ANON_KEY。',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  AppTextField(
                    controller: _emailController,
                    label: '邮箱',
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) =>
                        value == null || !value.contains('@') ? '请输入有效邮箱' : null,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _passwordController,
                    label: '密码',
                    obscureText: true,
                    validator: (value) =>
                        value == null || value.length < 6 ? '密码至少 6 位' : null,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed:
                        _submitting || !authRepository.isConfigured ? null : _submit,
                    child: _submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isLogin ? '登录' : '注册'),
                  ),
                  TextButton(
                    onPressed: () => context.go(isLogin ? '/register' : '/login'),
                    child: Text(isLogin ? '没有账号？注册' : '已有账号？登录'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
