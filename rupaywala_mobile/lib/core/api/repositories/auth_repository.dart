import '../api_client.dart';
import '../../models/auth_models.dart';
import '../../models/json_utils.dart';

/// Everything the login and registration screens need.
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  /// Decides between the login screen and the OTP screen for a phone number.
  Future<IdentityCheck> checkUser(String phoneNumber) async {
    final data = J.asMap(
      await _api.post('/auth/check-user', body: {'phone_number': phoneNumber}),
    );
    return IdentityCheck.fromJson(data);
  }

  Future<OtpDispatch> sendOtp(String phoneNumber) async {
    final data = J.asMap(
      await _api.post('/auth/send-otp', body: {'phone_number': phoneNumber}),
    );
    return OtpDispatch.fromJson(data);
  }

  Future<OtpDispatch> sendEmailOtp(String email) async {
    final data = J.asMap(
      await _api.post('/auth/send-email-otp', body: {'email': email}),
    );
    return OtpDispatch.fromJson(data);
  }

  Future<OtpVerificationResult> verifyOtp(
      String phoneNumber, String otp) async {
    final data = J.asMap(
      await _api.post(
        '/auth/verify-otp',
        body: {'phone_number': phoneNumber, 'otp': otp},
      ),
    );
    return OtpVerificationResult.fromJson(data);
  }

  Future<OtpVerificationResult> verifyEmailOtp(String email, String otp) async {
    final data = J.asMap(
      await _api.post(
        '/auth/verify-email-otp',
        body: {'email': email, 'otp': otp},
      ),
    );
    return OtpVerificationResult.fromJson(data);
  }

  /// `username` is required by the backend. The previous client sent `role`
  /// instead, which made every signup fail validation.
  Future<AuthResult> register({
    required String phoneNumber,
    required String username,
    required String password,
  }) async {
    final data = J.asMap(
      await _api.post(
        '/auth/register',
        body: {
          'phone_number': phoneNumber,
          'username': username,
          'password': password,
        },
      ),
    );
    return AuthResult.fromJson(data);
  }

  Future<AuthResult> registerEmail({
    required String email,
    required String username,
    required String password,
    String? phoneNumber,
  }) async {
    final body = <String, dynamic>{
      'email': email,
      'username': username,
      'password': password,
    };
    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      body['phone_number'] = phoneNumber.trim();
    }
    final data = J.asMap(
      await _api.post('/auth/register/email', body: body),
    );
    return AuthResult.fromJson(data);
  }

  Future<AuthResult> emailLogin({
    required String email,
    required String otp,
  }) async {
    final data = J.asMap(
      await _api.post(
        '/auth/email-login',
        body: {'email': email, 'otp': otp},
      ),
    );
    return AuthResult.fromJson(data);
  }

  Future<AuthResult> login({
    required String identifier,
    required String password,
  }) async {
    final data = J.asMap(
      await _api.post(
        '/auth/login',
        body: {'identifier': identifier, 'password': password},
      ),
    );
    return AuthResult.fromJson(data);
  }

  /// Re-checks a stored token on launch and after a 401.
  Future<AppSession> me() async {
    final data = J.asMap(await _api.get('/auth/me'));
    return AppSession.fromJson(data);
  }

  Future<void> logout() async {
    await _api.post('/auth/logout');
  }

  Future<void> changePassword({
    String? currentPassword,
    required String newPassword,
  }) async {
    final body = <String, dynamic>{'new_password': newPassword};
    if (currentPassword != null && currentPassword.isNotEmpty) {
      body['current_password'] = currentPassword;
    }
    await _api.post(
      '/auth/change-password',
      body: body,
    );
  }

  Future<String> changeUsername({
    required String username,
    String? currentPassword,
  }) async {
    final body = <String, dynamic>{'username': username};
    if (currentPassword != null && currentPassword.isNotEmpty) {
      body['current_password'] = currentPassword;
    }
    final data = J.asMap(
      await _api.put(
        '/auth/username',
        body: body,
      ),
    );
    return J.text(data['username']);
  }

  Future<void> sendForgotPasswordOtp(String phoneNumber) async {
    await _api.post(
      '/auth/forgot-password/send-otp',
      body: {'phone_number': phoneNumber},
    );
  }

  Future<void> resetPassword({
    required String phoneNumber,
    required String otp,
    required String newPassword,
  }) async {
    await _api.post(
      '/auth/forgot-password/reset',
      body: {
        'phone_number': phoneNumber,
        'otp': otp,
        'new_password': newPassword,
      },
    );
  }
}
