import 'package:dio/dio.dart';
import 'package:economy/core/sync/remote_transaction_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  test('syncBatch به endpoint POST می‌کند و نتیجه را پارس می‌کند', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    final adapter = DioAdapter(dio: dio);
    final tx = {'id': '1', 'kind': 'expense', 'amount_rial': 1000};

    adapter.onPost(
      '/sync/transactions/',
      (server) => server.reply(200, {
        'success': true,
        'results': [
          {'id': '1', 'status': 'created'},
        ],
      }),
      data: {'device_id': 'd', 'transactions': [tx]},
    );

    final api = DioRemoteTransactionApi(dio);
    final results = await api.syncBatch(deviceId: 'd', transactions: [tx]);

    expect(results, hasLength(1));
    expect(results.first['id'], '1');
    expect(results.first['status'], 'created');
  });
}
