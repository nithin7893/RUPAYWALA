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
import 'package:rupaywala_app/features/auth/email_input_screen.dart';
import 'package:rupaywala_app/features/auth/forgot_password_screen.dart';
import 'package:rupaywala_app/features/auth/otp_screen.dart';
import 'package:rupaywala_app/features/auth/password_login_screen.dart';
import 'package:rupaywala_app/features/auth/phone_input_screen.dart';
import 'package:rupaywala_app/features/auth/set_password_screen.dart';
import 'package:rupaywala_app/widgets/app_button.dart';

void main() {
  testWidgets('phone continue button updates as the number is entered',
      (tester) async {
    await tester.pumpWidget(_authHost(const PhoneInputScreen()));

    final continueButton = _button(tester, 'Continue');
    expect(continueButton.onPressed, isNull);

    await tester.enterText(find.byType(TextFormField).first, '9000000001');
    await tester.pump();

    expect(_button(tester, 'Continue').onPressed, isNotNull);
  });

  testWidgets('email continue button updates for a valid address',
      (tester) async {
    await tester.pumpWidget(_authHost(const EmailInputScreen()));

    expect(_button(tester, 'Continue with email').onPressed, isNull);

    await tester.enterText(
        find.byType(TextFormField).first, 'user@example.com');
    await tester.pump();

    expect(_button(tester, 'Continue with email').onPressed, isNotNull);
  });

  testWidgets('email flow calls the backend and shows delivery failure',
      (tester) async {
    http.Request? sentRequest;
    final tokenStore = _MemoryTokenStore();
    final api = Api(
      client: ApiClient(
        httpClient: MockClient((request) async {
          sentRequest = request;
          return http.Response(
            jsonEncode({
              'message': 'Delivery unavailable',
              'delivered': false,
              'expires_in_minutes': 5,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        tokenStore: tokenStore,
      ),
      tokenStore: tokenStore,
    );

    await tester.pumpWidget(_authHost(const EmailInputScreen(), api: api));
    await tester.enterText(
      find.byType(TextFormField).first,
      'user@example.com',
    );
    await tester.pump();
    await tester.tap(find.text('Continue with email'));
    await tester.pumpAndSettle();

    expect(sentRequest?.url.path, '/auth/send-email-otp');
    expect(jsonDecode(sentRequest!.body), {'email': 'user@example.com'});
    expect(find.text('Email could not be sent'), findsOneWidget);
  });

  testWidgets('password sign-in button updates as credentials are entered',
      (tester) async {
    await tester.pumpWidget(_authHost(const PasswordLoginScreen()));

    expect(_button(tester, 'Sign in').onPressed, isNull);

    await tester.enterText(find.byType(TextFormField).at(0), 'customer');
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.pump();

    expect(_button(tester, 'Sign in').onPressed, isNotNull);
  });

  testWidgets('password sign-in displays backend rejection and unlocks retry',
      (tester) async {
    final tokenStore = _MemoryTokenStore();
    final api = Api(
      client: ApiClient(
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'detail': 'Incorrect username/mobile number or password',
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
        tokenStore: tokenStore,
      ),
      tokenStore: tokenStore,
    );

    await tester.pumpWidget(
      _authHost(const PasswordLoginScreen(), api: api),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'customer');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong-password');
    await tester.pump();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(
      find.text('Incorrect username/mobile number or password'),
      findsOneWidget,
    );
    expect(_button(tester, 'Sign in').onPressed, isNotNull);
  });

  testWidgets('create-account displays backend rejection and unlocks retry',
      (tester) async {
    final tokenStore = _MemoryTokenStore();
    final api = Api(
      client: ApiClient(
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode({'detail': 'That username is already taken'}),
            409,
            headers: {'content-type': 'application/json'},
          );
        }),
        tokenStore: tokenStore,
      ),
      tokenStore: tokenStore,
    );

    await tester.pumpWidget(
      _authHost(
        const SetPasswordScreen(phoneNumber: '9000000001'),
        api: api,
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'customer');
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123');
    await tester.enterText(find.byType(TextFormField).at(2), 'Password123');
    await tester.pump();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('That username is already taken'), findsOneWidget);
    expect(_button(tester, 'Create account').onPressed, isNotNull);
  });

  testWidgets('email registration signs the new user into the app',
      (tester) async {
    final tokenStore = _WritableTokenStore();
    final api = Api(
      client: ApiClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/register/email') {
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
                'access_token': 'new-user-token',
                'user_id': 7,
                'role': 'customer',
                'username': 'newuser',
                'has_password': true,
              }),
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/auth/me') {
            expect(request.headers['Authorization'], 'Bearer new-user-token');
            return http.Response(
              jsonEncode({
                'user_id': 7,
                'role': 'customer',
                'username': 'newuser',
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
          fail('Unexpected backend request to ${request.url.path}');
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
        home: const SetPasswordScreen(
          email: 'new.user@example.com',
          method: OtpMethod.email,
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'newuser');
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123');
    await tester.enterText(find.byType(TextFormField).at(2), 'Password123');
    await tester.pump();
    await tester.tap(find.text('Create account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(session.isSignedIn, isTrue);
    expect(find.text('Create your password'), findsOneWidget);
  });

  testWidgets('forgot-password resend makes another backend request',
      (tester) async {
    var requestCount = 0;
    final tokenStore = _MemoryTokenStore();
    final api = Api(
      client: ApiClient(
        httpClient: MockClient((_) async {
          requestCount++;
          return http.Response(
            jsonEncode({'message': 'If registered, a code has been sent.'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        tokenStore: tokenStore,
      ),
      tokenStore: tokenStore,
    );

    await tester.pumpWidget(
      _authHost(
        const ForgotPasswordScreen(phoneNumber: '9000000001'),
        api: api,
      ),
    );
    await tester.pump();
    expect(requestCount, 1);

    await tester.pump(const Duration(seconds: 45));
    await tester.tap(find.text('Send a new code'));
    await tester.pumpAndSettle();

    expect(requestCount, 2);
  });

  testWidgets('create-account button updates as required fields are entered',
      (tester) async {
    await tester.pumpWidget(
      _authHost(const SetPasswordScreen(phoneNumber: '9000000001')),
    );

    expect(_button(tester, 'Create account').onPressed, isNull);

    await tester.enterText(find.byType(TextFormField).at(0), 'customer');
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123');
    await tester.enterText(find.byType(TextFormField).at(2), 'Password123');
    await tester.pump();

    expect(_button(tester, 'Create account').onPressed, isNotNull);
  });

  testWidgets('AppScope remains available to routes pushed on the navigator',
      (tester) async {
    final api = Api();
    final session = SessionController(api);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(
          api: api,
          session: session,
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (context) => Text(
                      '${identical(context.api, api)} '
                      '${identical(context.session, session)}',
                    ),
                  ),
                );
              },
              child: const Text('Open auth route'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open auth route'));
    await tester.pumpAndSettle();

    expect(find.text('true true'), findsOneWidget);
  });
}

Widget _authHost(Widget screen, {Api? api}) {
  final tokenStore = _MemoryTokenStore();
  final appApi = api ??
      Api(
        client: ApiClient(tokenStore: tokenStore),
        tokenStore: tokenStore,
      );
  final session = SessionController(appApi);
  addTearDown(session.dispose);

  return MaterialApp(
    builder: (context, child) => AppScope(
      api: appApi,
      session: session,
      child: child!,
    ),
    home: screen,
  );
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

class _WritableTokenStore extends TokenStore {
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

AppButton _button(WidgetTester tester, String label) {
  return tester.widget<AppButton>(
    find.byWidgetPredicate(
      (widget) => widget is AppButton && widget.label == label,
    ),
  );
}
