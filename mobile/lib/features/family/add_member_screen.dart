/// افزودنِ عضوِ خانواده توسطِ مدیر: شماره و رمزِ عضو را می‌سازد (حداکثر ۳ نفر).
/// عضو بعداً با همان شماره/رمز روی گوشیِ خودش وارد می‌شود.
library;

import 'package:flutter/material.dart';

import '../dashboard/dashboard_controller.dart';

const kAddMemberPhoneKey = Key('add-member-phone');
const kAddMemberPasswordKey = Key('add-member-password');
const kAddMemberNameKey = Key('add-member-name');
const kAddMemberSubmitKey = Key('add-member-submit');
const kAddMemberErrorKey = Key('add-member-error');

class AddMemberScreen extends StatefulWidget {
  final DashboardController controller;

  const AddMemberScreen({super.key, required this.controller});

  @override
  State<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends State<AddMemberScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = _phone.text.trim();
    final password = _password.text;
    if (phone.isEmpty || password.isEmpty) {
      setState(() => _error = 'شماره و رمز را کامل وارد کن');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.controller.addMember(
      phone: phone,
      password: password,
      fullName: _name.text,
    );
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('عضو اضافه شد.')));
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('افزودن عضو خانواده')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'شماره و رمزِ عضو را اینجا بساز؛ او با همین‌ها روی گوشیِ خودش وارد می‌شود.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            TextField(
              key: kAddMemberNameKey,
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'نام عضو (مثلاً مامان)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: kAddMemberPhoneKey,
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'شماره موبایل عضو',
                hintText: '09121234567',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: kAddMemberPasswordKey,
              controller: _password,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'رمز عبور عضو (حداقل ۴ کاراکتر)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: kAddMemberErrorKey,
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: kAddMemberSubmitKey,
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('ساخت و افزودن عضو'),
            ),
          ],
        ),
      ),
    );
  }
}
