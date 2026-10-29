import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rupaywala_app/core/api/api.dart';
import 'package:rupaywala_app/core/api/api_client.dart';
import 'package:rupaywala_app/core/api/token_store.dart';
import 'package:rupaywala_app/core/state/app_scope.dart';
import 'package:rupaywala_app/core/state/session_controller.dart';
import 'package:rupaywala_app/features/admin/admin_distance_rate_screen.dart';

void main() {
  testWidgets('distance rate screen loads its config with inherited AppScope',
      (tester) async {
    final tokenStore = _MemoryTokenStore();
    final api = Api(
      client: ApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/admin/distance-rate');
          return http.Response(
            jsonEncode({
              'threshold_km': 10,
              'rate_per_km': 12.5,
              'tax_percent': 18,
              'round_trip_factor': 2,
              'is_default': false,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        tokenStore: tokenStore,
      ),
      tokenStore: tokenStore,
    );
    final session = SessionController(api);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(
          api: api,
          session: session,
          child: child!,
        ),
        home: const AdminDistanceRateScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Current Rate'), findsOneWidget);
    expect(find.text('₹12.50 per km'), findsOneWidget);
    expect(find.text('Rate per KM (₹)'), findsOneWidget);
  });
}

class _MemoryTokenStore extends TokenStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> writeToken(
    String token, {
    String? role,
    String? displayName,
  }) async {}

  @override
  Future<void> clear() async {}
}
