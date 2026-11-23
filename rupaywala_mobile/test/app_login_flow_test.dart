import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rupaywala_app/core/api/api.dart';
import 'package:rupaywala_app/core/api/api_client.dart';
import 'package:rupaywala_app/core/api/token_store.dart';
import 'package:rupaywala_app/main.dart';
import 'package:rupaywala_app/widgets/app_button.dart';

void main() {
  testWidgets('successful password login opens the customer dashboard',
      (tester) async {
    final tokenStore = _MemoryTokenStore();
    final api = Api(
      client: ApiClient(
        httpClient: MockClient((request) async {
          final dashboardResponse =
              _customerDashboardResponse(request.url.path);
          if (dashboardResponse != null) return dashboardResponse;

          if (request.url.path == '/auth/login') {
            expect(
              jsonDecode(request.body),
              {'identifier': 'customer', 'password': 'Password123'},
            );
            return http.Response(
              jsonEncode({
                'access_token': 'test-token',
                'token_type': 'bearer',
                'user_id': 1,
                'role': 'customer',
                'username': 'customer',
                'is_verified': true,
                'profile_completed': false,
                'has_active_subscription': false,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.path == '/auth/me') {
            expect(
              request.headers['Authorization'],
              'Bearer test-token',
            );
            return http.Response(
              jsonEncode({
                'user_id': 1,
                'role': 'customer',
                'username': 'customer',
                'is_verified': true,
                'profile_completed': false,
                'account_status': 'active',
                'field_member': null,
                'subscription': null,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.path == '/subscriptions/plans') {
            return http.Response(
              jsonEncode([
                {
                  'id': 1,
                  'plan_name': 'Basic',
                  'price': 100,
                  'visits_included': 1,
                  'validity_days': 365,
                },
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          fail('Unexpected backend request to ${request.url.path}');
        }),
        tokenStore: tokenStore,
      ),
      tokenStore: tokenStore,
    );

    await tester.pumpWidget(RupaywalaApp(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with password'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'customer');
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123');
    await tester.pump();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is AppButton && widget.label == 'Sign in',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Request a service'), findsOneWidget);

    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(find.text('Test Customer'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    final subscriptionsAction = find.text('View plans').first;
    await tester.ensureVisible(subscriptionsAction);
    await tester.tap(subscriptionsAction);
    await tester.pumpAndSettle();

    expect(find.text('Membership'), findsOneWidget);
    expect(find.text('Basic'), findsOneWidget);
    expect(find.text('Get this plan'), findsOneWidget);
  });

  testWidgets('field-member credentials open the field dashboard',
      (tester) async {
    final tokenStore = _MemoryTokenStore();
    var loginAttempts = 0;
    final api = Api(
      client: ApiClient(
        httpClient: MockClient((request) async {
          final fieldDashboardResponse =
              _fieldDashboardResponse(request.url.path);
          if (fieldDashboardResponse != null) return fieldDashboardResponse;

          if (request.url.path == '/auth/login') {
            loginAttempts++;
            if (loginAttempts == 1) {
              return http.Response(
                jsonEncode({
                  'detail': 'Incorrect username/mobile number or password',
                }),
                401,
                headers: {'content-type': 'application/json'},
              );
            }
            expect(
              jsonDecode(request.body),
              {'identifier': 'agent01', 'password': 'AgentPass123'},
            );
            return http.Response(
              jsonEncode({
                'access_token': 'field-member-token',
                'token_type': 'bearer',
                'user_id': 41,
                'role': 'field_member',
                'username': 'agent01',
                'phone_number': '9000000010',
                'is_verified': true,
                'profile_completed': false,
                'has_active_subscription': false,
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
                'is_verified': true,
                'profile_completed': false,
                'account_status': 'active',
                'field_member': {
                  'id': 41,
                  'employee_code': 'AGENT-41',
                  'full_name': 'Test Agent',
                  'region': 'Chennai',
                  'approval_status': 'approved',
                  'is_available': true,
                },
                'subscription': null,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          fail('Unexpected backend request to ${request.url.path}');
        }),
        tokenStore: tokenStore,
      ),
      tokenStore: tokenStore,
    );

    await tester.pumpWidget(RupaywalaApp(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with password'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'agent01');
    await tester.enterText(find.byType(TextFormField).at(1), 'WrongPass123');
    await tester.pump();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is AppButton && widget.label == 'Sign in',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Incorrect username/mobile number or password'),
      findsOneWidget,
    );
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(1), 'AgentPass123');
    await tester.pump();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is AppButton && widget.label == 'Sign in',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text("TODAY'S VISITS"), findsOneWidget);
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(find.text('WORKLOAD'), findsOneWidget);
    expect(find.text('Employee AGENT-41'), findsOneWidget);
  });

  testWidgets('new email user reaches the dashboard after OTP registration',
      (tester) async {
    final tokenStore = _MemoryTokenStore();
    final api = Api(
      client: ApiClient(
        httpClient: MockClient((request) async {
          final dashboardResponse =
              _customerDashboardResponse(request.url.path);
          if (dashboardResponse != null) return dashboardResponse;

          switch (request.url.path) {
            case '/auth/send-email-otp':
              return http.Response(
                jsonEncode({
                  'message': 'Verification code sent.',
                  'delivered': true,
                  'expires_in_minutes': 5,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            case '/auth/verify-email-otp':
              return http.Response(
                jsonEncode({
                  'verified': true,
                  'next': 'register',
                  'user_exists': false,
                  'message': 'Verified.',
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            case '/auth/register/email':
              expect(
                jsonDecode(request.body),
                {
                  'email': 'new.user@example.com',
                  'username': 'newuser',
                  'password': 'Password123',
                },
              );
              return http.Response(
                jsonEncode({
                  'access_token': 'test-token',
                  'user_id': 2,
                  'role': 'customer',
                  'username': 'newuser',
                  'email': 'new.user@example.com',
                  'is_verified': true,
                  'profile_completed': false,
                  'has_active_subscription': false,
                }),
                201,
                headers: {'content-type': 'application/json'},
              );
            case '/auth/me':
              return http.Response(
                jsonEncode({
                  'user_id': 2,
                  'role': 'customer',
                  'username': 'newuser',
                  'email': 'new.user@example.com',
                  'is_verified': true,
                  'profile_completed': false,
                  'account_status': 'active',
                  'field_member': null,
                  'subscription': null,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            default:
              fail('Unexpected backend request to ${request.url.path}');
          }
        }),
        tokenStore: tokenStore,
      ),
      tokenStore: tokenStore,
    );

    await tester.pumpWidget(RupaywalaApp(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'new.user@example.com',
    );
    await tester.pump();
    await tester.tap(find.text('Continue with email'));
    await tester.pumpAndSettle();
    expect(find.text('Verify your email'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Create your password'), findsOneWidget);

    final fields = find.byType(TextFormField);
    final registrationFieldStart = fields.evaluate().length - 3;
    await tester.enterText(
      fields.at(registrationFieldStart),
      'newuser',
    );
    await tester.enterText(
      fields.at(registrationFieldStart + 1),
      'Password123',
    );
    await tester.enterText(
      fields.at(registrationFieldStart + 2),
      'Password123',
    );
    await tester.pump();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Request a service'), findsOneWidget);
    expect(find.text('Sign in with email'), findsNothing);
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

http.Response? _customerDashboardResponse(String path) {
  if (path == '/subscriptions/my-subscription') {
    return _jsonResponse(
      {'detail': 'No active subscription'},
      status: 404,
    );
  }

  final body = switch (path) {
    '/profile/me' => {
        'id': 1,
        'full_name': 'Test Customer',
        'profile_completed': false,
      },
    '/policies/list' ||
    '/service/my-requests' ||
    '/subscriptions/my-subscriptions' ||
    '/subscriptions/visits/history' =>
      <Object?>[],
    '/subscriptions/visits/balance' => <String, Object?>{},
    '/notifications/unread-count' => {'unread_count': 0},
    _ => null,
  };
  return body == null ? null : _jsonResponse(body);
}

http.Response? _fieldDashboardResponse(String path) {
  final body = switch (path) {
    '/field-member/my-profile' => {
        'field_member_id': 41,
        'employee_code': 'AGENT-41',
        'full_name': 'Test Agent',
        'region': 'Chennai',
        'approval_status': 'approved',
        'is_available': true,
      },
    '/field-member/my-stats' => <String, Object?>{},
    '/field-member/my-assignments' => <Object?>[],
    '/notifications/unread-count' => {'unread_count': 0},
    _ => null,
  };
  return body == null ? null : _jsonResponse(body);
}

http.Response _jsonResponse(Object body, {int status = 200}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}
