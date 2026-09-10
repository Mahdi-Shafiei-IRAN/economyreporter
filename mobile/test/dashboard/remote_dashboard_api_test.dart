import 'package:dio/dio.dart';
import 'package:economy/core/dashboard/remote_dashboard_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  test('fetchSummary پاسخ سرور را به مدل تبدیل می‌کند', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    final adapter = DioAdapter(dio: dio);

    adapter.onGet(
      '/dashboard/summary/',
      (server) => server.reply(200, {
        'period': {'from': null, 'to': null},
        'family': {'income': 10000000, 'expenses': 3000000, 'balance': 7000000},
        'members': [
          {'id': 'u1', 'name': 'علی', 'expenses': 3000000},
        ],
        'categories': [
          {'category': 'c1', 'name': 'خوراک', 'amount': 3000000},
        ],
        'cards': [
          {'card': 'k1', 'card_last4': '1234', 'amount': 3000000},
        ],
      }),
    );

    final api = DioRemoteDashboardApi(dio);
    final s = await api.fetchSummary();

    expect(s.incomeRial, 10000000);
    expect(s.expenseRial, 3000000);
    expect(s.balanceRial, 7000000);
    expect(s.members.single.name, 'علی');
    expect(s.categories.single.name, 'خوراک');
    expect(s.cards.single.cardLast4, '1234');
  });
}
