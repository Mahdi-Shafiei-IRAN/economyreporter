/// افزودنِ عضوِ خانواده توسطِ مدیر: شماره و رمزِ عضو را می‌سازد (حداکثر ۳ نفر).
/// عضو بعداً با همان شماره/رمز روی گوشیِ خودش وارد می‌شود.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/family/family_api.dart';
import '../transactions/data/transaction_repository.dart';

const kAddMemberPhoneKey = Key('add-member-phone');
const kAddMemberPasswordKey = Key('add-member-password');
const kAddMemberNameKey = Key('add-member-name');
const kAddMemberSubmitKey = Key('add-member-submit');
const kAddMemberErrorKey = Key('add-member-error');

typedef AddMemberFn = Future<String?> Function(
    {required String phone, required String password, String? fullName});

/// افزودنِ عضو با سرور و تازه کردنِ فهرستِ اعضا روی گوشی؛ خطا = پیامِ فارسی، موفق = null.
Future<String?> addFamilyMember(
  FamilyApi api,
  TransactionStore store, {
  required String phone,
  required String password,
  String? fullName,
}) async {
  try {
    await api.addMember(phone: phone, password: password, fullName: fullName);
    await store.setSetting(SettingKeys.familyMembers, FamilyMember.encodeList(await api.members()));
    return null;
  } on DioException catch (e) {
    final data = e.response?.data;
    if (data is Map) {
      for (final f in const ['phone', 'password', 'detail', 'non_field_errors']) {
        final v = data[f];
        if (v is List && v.isNotEmpty) return v.first.toString();
        if (v is String) return v;
      }
    }
    if (e.response?.statusCode == 403) return 'فقط مدیرِ خانواده می‌تواند عضو اضافه کند';
    return 'خطا در افزودن عضو';
  } catch (_) {
    return 'خطا در افزودن عضو';
  }
}

class AddMemberScreen extends StatefulWidget {
  final AddMemberFn onAdd;

  const AddMemberScreen({super.key, required this.onAdd});

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
    final err = await widget.onAdd(
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
