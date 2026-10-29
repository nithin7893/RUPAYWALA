import 'json_utils.dart';

/// The three shells the app can render.
enum AppRole {
  customer,
  fieldMember,
  admin;

  static AppRole fromWire(String? value) {
    switch (value) {
      case 'admin':
        return AppRole.admin;
      case 'field_member':
        return AppRole.fieldMember;
      default:
        return AppRole.customer;
    }
  }

  String get wireName => switch (this) {
        AppRole.customer => 'customer',
        AppRole.fieldMember => 'field_member',
        AppRole.admin => 'admin',
      };

  String get label => switch (this) {
        AppRole.customer => 'Customer',
        AppRole.fieldMember => 'Field Member',
        AppRole.admin => 'Admin',
      };
}

/// Visit allowance carried on the session so every screen can show it without
/// an extra round trip.
class SessionSubscription {
  final int id;
  final String status;
  final String? planName;
  final int totalVisits;
  final int usedVisits;
  final int remainingVisits;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool usable;

  const SessionSubscription({
    required this.id,
    required this.status,
    this.planName,
    this.totalVisits = 0,
    this.usedVisits = 0,
    this.remainingVisits = 0,
    this.startDate,
    this.endDate,
    this.usable = false,
  });

  factory SessionSubscription.fromJson(Map<String, dynamic> json) {
    return SessionSubscription(
      id: J.integer(json['id']),
      status: J.text(json['status'], 'none'),
      planName: J.str(json['plan_name']),
      totalVisits: J.integer(json['total_visits']),
      usedVisits: J.integer(json['used_visits']),
      remainingVisits: J.integer(json['remaining_visits']),
      startDate: J.parse(json['start_date']),
      endDate: J.parse(json['end_date']),
      usable: J.flag(json['usable']),
    );
  }

  bool get isActive => status == 'active';
}

/// The signed-in user, restored from `GET /auth/me` on app launch.
class AppSession {
  final int userId;
  final AppRole role;
  final String? username;
  final String? fullName;
  final String? phoneNumber;
  final String? email;
  final bool profileCompleted;
  final bool isVerified;
  final String accountStatus;
  final bool hasPassword;

  /// Field-member-only details, present when the role is fieldMember.
  final FieldMemberSummary? fieldMember;

  final SessionSubscription? subscription;

  const AppSession({
    required this.userId,
    required this.role,
    this.username,
    this.fullName,
    this.phoneNumber,
    this.email,
    this.profileCompleted = false,
    this.isVerified = true,
    this.accountStatus = 'active',
    this.hasPassword = false,
    this.fieldMember,
    this.subscription,
  });

  factory AppSession.fromJson(Map<String, dynamic> json) {
    return AppSession(
      userId: J.integer(json['user_id']),
      role: AppRole.fromWire(J.str(json['role'])),
      username: J.str(json['username']),
      fullName: J.str(json['full_name']),
      phoneNumber: J.str(json['phone_number']),
      email: J.str(json['email']),
      profileCompleted: J.flag(json['profile_completed']),
      isVerified: J.flag(json['is_verified'], fallback: true),
      accountStatus: J.text(json['account_status'], 'active'),
      hasPassword: J.flag(json['has_password']),
      fieldMember: J.object(json['field_member']) == null
          ? null
          : FieldMemberSummary.fromJson(J.asMap(json['field_member'])),
      subscription: J.object(json['subscription']) == null
          ? null
          : SessionSubscription.fromJson(J.asMap(json['subscription'])),
    );
  }

  AppSession copyWith({String? username}) {
    return AppSession(
      userId: userId,
      role: role,
      username: username ?? this.username,
      fullName: fullName,
      phoneNumber: phoneNumber,
      email: email,
      profileCompleted: profileCompleted,
      isVerified: isVerified,
      accountStatus: accountStatus,
      hasPassword: hasPassword,
      fieldMember: fieldMember,
      subscription: subscription,
    );
  }

  /// Best available human name for greetings and the avatar.
  String get displayName {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final handle = username?.trim();
    if (handle != null && handle.isNotEmpty) return handle;
    return 'there';
  }

  bool get hasUsableSubscription => subscription?.usable ?? false;
}

class FieldMemberSummary {
  final int id;
  final String? employeeCode;
  final String? fullName;
  final String? region;
  final String approvalStatus;
  final bool isAvailable;

  const FieldMemberSummary({
    required this.id,
    this.employeeCode,
    this.fullName,
    this.region,
    required this.approvalStatus,
    this.isAvailable = false,
  });

  factory FieldMemberSummary.fromJson(Map<String, dynamic> json) {
    return FieldMemberSummary(
      id: J.integer(json['id']),
      employeeCode: J.str(json['employee_code']),
      fullName: J.str(json['full_name']),
      region: J.str(json['region']),
      approvalStatus: J.text(json['approval_status'], 'pending'),
      isAvailable: J.flag(json['is_available']),
    );
  }

  String get displayName {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final code = employeeCode?.trim();
    if (code != null && code.isNotEmpty) return code;
    return 'Field member';
  }
}

/// The result of a successful login / registration.
class AuthResult {
  final String accessToken;
  final int userId;
  final AppRole role;
  final String? username;
  final String? fullName;
  final String? phoneNumber;
  final bool profileCompleted;
  final bool hasActiveSubscription;
  final bool hasPassword;

  const AuthResult({
    required this.accessToken,
    required this.userId,
    required this.role,
    this.username,
    this.fullName,
    this.phoneNumber,
    this.profileCompleted = false,
    this.hasActiveSubscription = false,
    this.hasPassword = false,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      accessToken: J.text(json['access_token']),
      userId: J.integer(json['user_id']),
      role: AppRole.fromWire(J.str(json['role'])),
      username: J.str(json['username']),
      fullName: J.str(json['full_name']),
      phoneNumber: J.str(json['phone_number']),
      profileCompleted: J.flag(json['profile_completed']),
      hasActiveSubscription: J.flag(json['has_active_subscription']),
      hasPassword: J.flag(json['has_password']),
    );
  }
}

/// Response of `POST /auth/check-user`, which decides which screen the app
/// shows after a phone number is entered.
class IdentityCheck {
  final bool exists;
  final bool hasPassword;
  final String next;

  const IdentityCheck({
    required this.exists,
    required this.hasPassword,
    required this.next,
  });

  factory IdentityCheck.fromJson(Map<String, dynamic> json) {
    return IdentityCheck(
      exists: J.flag(json['exists']),
      hasPassword: J.flag(json['has_password']),
      next: J.text(json['next'], 'send_otp'),
    );
  }
}

/// Response of `POST /auth/verify-otp`.
class OtpVerificationResult {
  final bool verified;
  final String next;
  final bool userExists;
  final String message;

  const OtpVerificationResult({
    required this.verified,
    required this.next,
    required this.userExists,
    required this.message,
  });

  factory OtpVerificationResult.fromJson(Map<String, dynamic> json) {
    return OtpVerificationResult(
      verified: J.flag(json['verified']),
      next: J.text(json['next'], 'register'),
      userExists: J.flag(json['user_exists']),
      message: J.text(json['message']),
    );
  }
}

class OtpDispatch {
  final bool delivered;
  final int expiresInMinutes;

  const OtpDispatch({required this.delivered, required this.expiresInMinutes});

  factory OtpDispatch.fromJson(Map<String, dynamic> json) {
    return OtpDispatch(
      delivered: J.flag(json['delivered']),
      expiresInMinutes: J.integer(json['expires_in_minutes'], 5),
    );
  }
}
