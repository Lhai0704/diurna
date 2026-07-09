import 'package:diurna/features/auth/presentation/auth_form.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthForm(mode: AuthFormMode.login);
  }
}
