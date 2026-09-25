/// سلامتِ گوشی‌ها روی سرور: هر گوشی خلاصه‌ی خودش را می‌فرستد و مدیرِ خانواده گوشی‌های
/// همه را می‌بیند (عضوِ عادی فقط گوشی‌های خودش را).
library;

import 'package:dio/dio.dart';

import '../auth/auth_repository.dart';
import '../diagnostics/device_health.dart';

/// گزارشِ یک گوشی که از سرور آمده.
class RemoteDeviceHealth {
  final String userId;
  final String userName;
  final String deviceId;
  final String appVersion;
  final HealthLevel level;
  final DeviceHealthReport report;

  /// زمانی که سرور گزارش را گرفت.
  final DateTime? receivedAt;

  const RemoteDeviceHealth({
    required this.userId,
    required this.userName,
    required this.deviceId,
    required this.appVersion,
    required this.level,
    required this.report,
    this.receivedAt,
  });

  factory RemoteDeviceHealth.fromJson(Map<String, dynamic> j) {
    final user = UserProfile.fromJson(Map<String, dynamic>.from(j['user'] as Map));
    return RemoteDeviceHealth(
      userId: user.id,
      userName: user.displayName,
      deviceId: '${j['device_id']}',
      appVersion: '${j['app_version'] ?? ''}',
      level: HealthLevel.parse(j['level'] as String?),
      report: DeviceHealthReport.fromJson(
          j['summary'] is Map ? Map<String, dynamic>.from(j['summary'] as Map) : const {}),
      receivedAt: DateTime.tryParse('${j['updated_at']}'),
    );
  }
}

abstract class HealthApi {
  Future<void> report({required String deviceId, required DeviceHealthReport report});
  Future<List<RemoteDeviceHealth>> family();
}

class DioHealthApi implements HealthApi {
  final Dio dio;
  DioHealthApi(this.dio);

  @override
  Future<void> report({required String deviceId, required DeviceHealthReport report}) async {
    await dio.post('/family/health/', data: {
      'device_id': deviceId,
      'app_version': report.appVersion ?? '',
      'level': report.level.name,
      'summary': report.toJson(),
      'reported_at': report.at.toUtc().toIso8601String(),
    });
  }

  @override
  Future<List<RemoteDeviceHealth>> family() async {
    final resp = await dio.get('/family/health/');
    return [
      for (final e in (resp.data as List? ?? const []))
        RemoteDeviceHealth.fromJson(Map<String, dynamic>.from(e as Map)),
    ];
  }
}
