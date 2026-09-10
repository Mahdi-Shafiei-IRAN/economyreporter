/// کلاینت داشبورد خانواده از سرور. اینترفیس تزریق‌پذیر تا در تست fake شود.
library;

import 'package:dio/dio.dart';

import 'dashboard_summary.dart';

abstract class RemoteDashboardApi {
  Future<DashboardSummary> fetchSummary({DateTime? from, DateTime? to});
}

class DioRemoteDashboardApi implements RemoteDashboardApi {
  final Dio dio;

  DioRemoteDashboardApi(this.dio);

  @override
  Future<DashboardSummary> fetchSummary({DateTime? from, DateTime? to}) async {
    final query = <String, dynamic>{};
    if (from != null) query['from'] = from.toIso8601String();
    if (to != null) query['to'] = to.toIso8601String();
    final resp = await dio.get('/dashboard/summary/', queryParameters: query);
    return DashboardSummary.fromJson(Map<String, dynamic>.from(resp.data));
  }
}
