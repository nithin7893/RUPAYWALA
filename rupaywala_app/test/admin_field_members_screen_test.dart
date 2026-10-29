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
import 'package:rupaywala_app/features/admin/admin_field_members_screen.dart';

void main() {
  testWidgets('admin can create and deactivate a field member', (tester) async {
    var created = false;
    var deactivated = false;
    final tokenStore = _MemoryTokenStore();
    final api = Api(
      client: ApiClient(
        httpClient: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/admin/field-members') {
            return http.Response(
              jsonEncode(
                created ? [_memberJson] : <Map<String, Object?>>[],
              ),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/admin/field-members') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['username'], 'agent01');
            expect(body['password'], 'AgentPass123');
            expect(body['full_name'], 'Test Agent');
            expect(body['phone_number'], '9000000010');
            created = true;
            return http.Response(
              jsonEncode(_memberJson),
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'DELETE' &&
              request.url.path == '/admin/field-members/41') {
            deactivated = true;
            return http.Response(
              jsonEncode({'message': 'Field member access removed'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          fail('Unexpected request: ${request.method} ${request.url.path}');
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
        home: const AdminFieldMembersScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No Field Members'), findsOneWidget);

    await tester.tap(find.byTooltip('Add field member'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Test Agent');
    await tester.enterText(fields.at(1), 'agent01');
    await tester.enterText(fields.at(2), 'AgentPass123');
    await tester.enterText(fields.at(3), '9000000010');
    await tester.tap(find.text('Create member'));
    await tester.pumpAndSettle();

    expect(created, isTrue);
    expect(find.text('Test Agent'), findsOneWidget);
    expect(find.text('@agent01 · 9000000010'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove field member access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove access'));
    await tester.pumpAndSettle();

    expect(deactivated, isTrue);
    expect(find.text('Access removed'), findsOneWidget);
  });
}

const _memberJson = {
  'id': 41,
  'user_id': 72,
  'employee_code': 'AGENT-41',
  'full_name': 'Test Agent',
  'region': 'Chennai',
  'phone_number': '9000000010',
  'username': 'agent01',
  'approval_status': 'approved',
  'is_available': true,
  'is_active': true,
  'active_jobs': 0,
  'completed_jobs': 0,
};

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
