import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:rupaywala_app/core/api/api.dart';
import 'package:rupaywala_app/core/api/api_client.dart';
import 'package:rupaywala_app/core/api/token_store.dart';
import 'package:rupaywala_app/core/state/app_scope.dart';
import 'package:rupaywala_app/core/state/session_controller.dart';
import 'package:rupaywala_app/features/payment/payment_screen.dart';
import 'package:rupaywala_app/widgets/app_button.dart';

void main() {
  testWidgets('payment screen generates QR from the payment UPI URL',
      (tester) async {
    final tokenStore = _MemoryTokenStore();
    await tokenStore.writeToken('test-token');
    final api = Api(
      client: ApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/payments/create');
          expect(jsonDecode(request.body), {'plan_id': 7});
          return http.Response(
            jsonEncode({
              'txn_id': 'test-transaction',
              'payment_type': 'subscription',
              'amount': 499,
              'base_amount': 499,
              'extra_charge': 0,
              'tax_amount': 0,
              'currency': 'INR',
              'upi_url':
                  'upi://pay?pa=merchant%40upi&pn=Rupaywala&am=499.00&cu=INR&tn=test',
              'qr_code': '',
              'status': 'pending',
              'plan_id': 7,
              'plan_name': 'Basic',
              'expires_at': '2026-10-26T15:10:00',
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
        home: const PaymentScreen(
          planId: 7,
          planName: 'Basic',
          amount: 499,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Scan QR to Pay'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppButton && widget.label == 'Pay via UPI App',
      ),
      findsOneWidget,
    );
  });

  testWidgets('payment setup errors are visible and can be retried',
      (tester) async {
    final tokenStore = _MemoryTokenStore();
    final api = Api(
      client: ApiClient(
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({'detail': 'Payment provider unavailable'}),
              503,
              headers: {'content-type': 'application/json'},
            )),
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
        home: const PaymentScreen(
          planId: 7,
          planName: 'Basic',
          amount: 499,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Payment provider unavailable'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppButton && widget.label == 'Retry',
      ),
      findsOneWidget,
    );
  });
}

class _MemoryTokenStore extends TokenStore {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> writeToken(
    String token, {
    String? role,
    String? displayName,
  }) async {
    _token = token;
  }

  @override
  Future<void> clear() async {
    _token = null;
  }
}
