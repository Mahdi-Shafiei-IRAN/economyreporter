/// ثبت‌نامِ آزاد: هرکس حساب و خانواده‌ی خودش را می‌سازد و مالکش می‌شود.
/// بعد می‌تواند تا ۳ نفر عضو اضافه کند (در صفحه‌ی خانواده).
library;

import 'package:flutter/material.dart';

import 'auth_controller.dart';

const kRegPhoneKey = Key('register-phone');
const kRegPasswordKey = Key('register-password');
const kRegNameKey = Key('register-name');
const kRegFamilyKey = Key('register-family');
const kRegSubmitKey = Key('register-submit');
const kRegErrorKey = Key('register-error');

class RegisterScreen extends StatefulWidget {
  final AuthController controller;

  const RegisterScreen({super.key, required this.controller});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _family = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _name.dispose();
    _family.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = _phone.text.trim();
    final password = _password.text;
    if (phone.isEmpty || password.isEmpty) return;
    final ok = await widget.controller.register(
      phone: phone,
      password: password,
      fullName: _name.text,
      familyName: _family.text,
    );
    if (ok && mounted) Navigator.of(context).pop(); // ریشه به authenticated واکنش می‌دهد
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ساخت خانواده‌ی جدید')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final c = widget.controller;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'برای خودت حساب بساز؛ تو مدیرِ خانواده می‌شوی و بعد می‌توانی '
                    'تا ۳ نفر عضو اضافه کنی.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    key: kRegNameKey,
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'نام تو (مثلاً بابا)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: kRegPhoneKey,
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'شماره موبایل',
                      hintText: '09121234567',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: kRegPasswordKey,
                    controller: _password,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'رمز عبور (حداقل ۴ کاراکتر)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: kRegFamilyKey,
                    controller: _family,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'نام خانواده (اختیاری)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (c.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      c.error!,
                      key: kRegErrorKey,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    key: kRegSubmitKey,
                    onPressed: c.loading ? null : _submit,
                    child: c.loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('ساخت حساب و ورود'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
