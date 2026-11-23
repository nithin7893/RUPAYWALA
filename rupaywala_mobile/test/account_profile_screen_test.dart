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
import 'package:rupaywala_app/features/profile/account_profile_screen.dart';
import 'package:rupaywala_app/widgets/app_button.dart';

void main() {
  testWidgets('users can view their account and change username and password',
      (tester) async {
    final tokenStore = _MemoryTokenStore();
    var passwordChanged = false;
    final api = Api(
      client: ApiClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/login') {
            return http.Response(
              jsonEncode({
                'access_token': 'profile-token',
                'user_id': 41,
                'role': 'field_member',
                'username': 'agent01',
                'phone_number': '9000000010',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/auth/me') {
            return http.Response(
              jsonEncode({
                'user_id': 41,
                'role': 'field_member',
                'username': 'agent01',
                'phone_number': '9000000010',
                'account_status': 'active',
                'has_password': true,
                'field_member': {
                  'id': 41,
                  'employee_code': 'AGENT-41',
                  'full_name': 'Test Agent',
                  'region': 'Chennai',
                  'approval_status': 'approved',
                  'is_available': true,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/auth/username') {
            expect(request.method, 'PUT');
            expect(
              jsonDecode(request.body),
              {
                'username': 'agent.02',
                'current_password': 'CurrentPass123',
              },
            );
            return http.Response(
              jsonEncode({'username': 'agent.02'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/auth/change-password') {
            expect(
              jsonDecode(request.body),
              {
                'current_password': 'CurrentPass123',
                'new_password': 'NewPass123',
              },
            );
            passwordChanged = true;
            return http.Response(
              jsonEncode({'message': 'Password updated successfully'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          fail('Unexpected backend request: ${request.method} ${request.url}');
        }),
        tokenStore: tokenStore,
      ),
      tokenStore: tokenStore,
    );
    final session = SessionController(api);
    addTearDown(session.dispose);
    await session.login(identifier: 'agent01', password: 'CurrentPass123');
    expect(session.isSignedIn, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(
          api: api,
          session: session,
          child: child!,
        ),
        home: const AccountProfileScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Agent'), findsOneWidget);
    expect(find.text('Field Member'), findsOneWidget);
    expect(find.text('AGENT-41'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'agent.02');
    await tester.enterText(fields.at(1), 'CurrentPass123');
    final updateUsernameButton = find.byWidgetPredicate(
      (widget) => widget is AppButton && widget.label == 'Update username',
    );
    await tester.scrollUntilVisible(
      updateUsernameButton,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(updateUsernameButton);
    await tester.pumpAndSettle();
    expect(find.text('Username updated successfully.'), findsOneWidget);
    expect(find.text('agent.02'), findsOneWidget);

    await tester.enterText(fields.at(2), 'CurrentPass123');
    await tester.enterText(fields.at(3), 'NewPass123');
    await tester.enterText(fields.at(4), 'NewPass123');
    final updatePasswordButton = find.byWidgetPredicate(
      (widget) => widget is AppButton && widget.label == 'Update password',
    );
    await tester.scrollUntilVisible(
      updatePasswordButton,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(updatePasswordButton);
    await tester.pumpAndSettle();
    expect(passwordChanged, isTrue);
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
