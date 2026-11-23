import 'json_utils.dart';
import 'service_models.dart';

/// `FieldMemberJobResponse` — a field member's view of an assigned request.
class FieldMemberJob {
  final int assignmentId;
  final int requestId;
  final String reference;
  final String status;
  final String statusLabel;
  final String requestType;
  final String? description;
  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;
  final double? customerLatitude;
  final double? customerLongitude;
  final String? policyLabel;
  final String? branchName;
  final String? branchAddress;
  final double? distanceKm;
  final String? completionNotes;
  final String? proofImageUrl;
  final String? proofDocumentId;
  final DateTime? assignedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? createdAt;

  const FieldMemberJob({
    required this.assignmentId,
    required this.requestId,
    required this.reference,
    required this.status,
    required this.statusLabel,
    required this.requestType,
    this.description,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.customerLatitude,
    this.customerLongitude,
    this.policyLabel,
    this.branchName,
    this.branchAddress,
    this.distanceKm,
    this.completionNotes,
    this.proofImageUrl,
    this.proofDocumentId,
    this.assignedAt,
    this.startedAt,
    this.completedAt,
    this.createdAt,
  });

  factory FieldMemberJob.fromJson(Map<String, dynamic> json) {
    return FieldMemberJob(
      assignmentId: J.integer(json['assignment_id']),
      requestId: J.integer(json['request_id']),
      reference: J.text(json['reference'], '#${J.integer(json['request_id'])}'),
      status: J.text(json['status'], 'assigned'),
      statusLabel: J.text(json['status_label'], 'Assigned'),
      requestType: J.text(json['request_type']),
      description: J.str(json['description']),
      customerName: J.str(json['customer_name']),
      customerPhone: J.str(json['customer_phone']),
      customerAddress: J.str(json['customer_address']),
      customerLatitude: json['customer_latitude'] == null
          ? null
          : J.dbl(json['customer_latitude']),
      customerLongitude: json['customer_longitude'] == null
          ? null
          : J.dbl(json['customer_longitude']),
      policyLabel: J.str(json['policy_label']),
      branchName: J.str(json['branch_name']),
      branchAddress: J.str(json['branch_address']),
      distanceKm:
          json['distance_km'] == null ? null : J.dbl(json['distance_km']),
      completionNotes: J.str(json['completion_notes']),
      proofImageUrl: J.str(json['proof_image_url']),
      proofDocumentId: J.str(json['proof_document_id']),
      assignedAt: J.parse(json['assigned_at']),
      startedAt: J.parse(json['started_at']),
      completedAt: J.parse(json['completed_at']),
      createdAt: J.parse(json['created_at']),
    );
  }

  RequestStage get stage => RequestStage.fromWire(status);

  bool get canStart => stage == RequestStage.assigned;

  bool get canComplete => stage == RequestStage.inProgress;

  bool get isDone => stage == RequestStage.completed;

  String get customerDisplayName {
    final name = customerName?.trim();
    return name == null || name.isEmpty ? 'Customer' : name;
  }
}

/// `GET /field-member/my-stats`
class FieldMemberStats {
  final int assigned;
  final int inProgress;
  final int completed;
  final int completedToday;

  const FieldMemberStats({
    this.assigned = 0,
    this.inProgress = 0,
    this.completed = 0,
    this.completedToday = 0,
  });

  factory FieldMemberStats.fromJson(Map<String, dynamic> json) {
    return FieldMemberStats(
      assigned: J.integer(json['assigned']),
      inProgress: J.integer(json['in_progress']),
      completed: J.integer(json['completed']),
      completedToday: J.integer(json['completed_today']),
    );
  }

  int get openTotal => assigned + inProgress;
}

/// `GET /field-member/my-profile`
class FieldMemberProfile {
  final int fieldMemberId;
  final String? employeeCode;
  final String? fullName;
  final String? region;
  final String? phoneNumber;
  final String? username;
  final String approvalStatus;
  final bool isAvailable;
  final FieldMemberStats stats;

  const FieldMemberProfile({
    required this.fieldMemberId,
    this.employeeCode,
    this.fullName,
    this.region,
    this.phoneNumber,
    this.username,
    required this.approvalStatus,
    this.isAvailable = false,
    this.stats = const FieldMemberStats(),
  });

  factory FieldMemberProfile.fromJson(Map<String, dynamic> json) {
    final stats = J.object(json['stats']);
    return FieldMemberProfile(
      fieldMemberId: J.integer(json['field_member_id']),
      employeeCode: J.str(json['employee_code']),
      fullName: J.str(json['full_name']),
      region: J.str(json['region']),
      phoneNumber: J.str(json['phone_number']),
      username: J.str(json['username']),
      approvalStatus: J.text(json['approval_status'], 'pending'),
      isAvailable: J.flag(json['is_available']),
      stats: stats == null
          ? const FieldMemberStats()
          : FieldMemberStats.fromJson(stats),
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

/// `GET /admin/field-members`
class ManagedFieldMember {
  final int id;
  final int userId;
  final String? employeeCode;
  final String? fullName;
  final String? region;
  final String? phoneNumber;
  final String? username;
  final String approvalStatus;
  final bool isAvailable;
  final bool isActive;
  final int activeJobs;
  final int completedJobs;
  final String? rejectionReason;
  final DateTime? approvedAt;
  final DateTime? createdAt;

  const ManagedFieldMember({
    required this.id,
    required this.userId,
    this.employeeCode,
    this.fullName,
    this.region,
    this.phoneNumber,
    this.username,
    required this.approvalStatus,
    this.isAvailable = false,
    this.isActive = true,
    this.activeJobs = 0,
    this.completedJobs = 0,
    this.rejectionReason,
    this.approvedAt,
    this.createdAt,
  });

  factory ManagedFieldMember.fromJson(Map<String, dynamic> json) {
    return ManagedFieldMember(
      id: J.integer(json['id']),
      userId: J.integer(json['user_id']),
      employeeCode: J.str(json['employee_code']),
      fullName: J.str(json['full_name']),
      region: J.str(json['region']),
      phoneNumber: J.str(json['phone_number']),
      username: J.str(json['username']),
      approvalStatus: J.text(json['approval_status'], 'pending'),
      isAvailable: J.flag(json['is_available']),
      isActive: J.flag(json['is_active'], fallback: true),
      activeJobs: J.integer(json['active_jobs']),
      completedJobs: J.integer(json['completed_jobs']),
      rejectionReason: J.str(json['rejection_reason']),
      approvedAt: J.parse(json['approved_at']),
      createdAt: J.parse(json['created_at']),
    );
  }

  String get displayName {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final code = employeeCode?.trim();
    if (code != null && code.isNotEmpty) return code;
    return 'Field member $id';
  }

  bool get isPending => approvalStatus == 'pending';
  bool get isApproved => approvalStatus == 'approved';
}

/// `GET /admin/dashboard`
class AdminDashboardStats {
  final int totalCustomers;
  final int totalFieldMembers;
  final int pendingFieldMembers;
  final int totalServiceRequests;
  final int openRequests;
  final int inProgressRequests;
  final int completedToday;
  final int cancelledRequests;
  final int activeSubscriptions;
  final int expiringSubscriptions;
  final int pendingPayments;
  final int successfulPayments;
  final double totalCollected;

  const AdminDashboardStats({
    this.totalCustomers = 0,
    this.totalFieldMembers = 0,
    this.pendingFieldMembers = 0,
    this.totalServiceRequests = 0,
    this.openRequests = 0,
    this.inProgressRequests = 0,
    this.completedToday = 0,
    this.cancelledRequests = 0,
    this.activeSubscriptions = 0,
    this.expiringSubscriptions = 0,
    this.pendingPayments = 0,
    this.successfulPayments = 0,
    this.totalCollected = 0,
  });

  factory AdminDashboardStats.fromJson(Map<String, dynamic> json) {
    final payments = J.asMap(json['payments']);
    return AdminDashboardStats(
      totalCustomers: J.integer(json['total_customers']),
      totalFieldMembers: J.integer(json['total_field_members']),
      pendingFieldMembers: J.integer(json['pending_field_members']),
      totalServiceRequests: J.integer(json['total_service_requests']),
      openRequests: J.integer(json['open_requests']),
      inProgressRequests: J.integer(json['in_progress_requests']),
      completedToday: J.integer(json['completed_today']),
      cancelledRequests: J.integer(json['cancelled_requests']),
      activeSubscriptions: J.integer(json['active_subscriptions']),
      expiringSubscriptions: J.integer(json['expiring_subscriptions']),
      pendingPayments: J.integer(payments['pending_verification']),
      successfulPayments: J.integer(payments['success']),
      totalCollected: J.dbl(payments['total_collected']),
    );
  }
}

/// `GET /admin/users`
class ManagedUser {
  final int id;
  final String? username;
  final String? fullName;
  final String? phoneNumber;
  final String? email;
  final String role;
  final bool isVerified;
  final String accountStatus;
  final bool profileCompleted;
  final bool hasActiveSubscription;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  const ManagedUser({
    required this.id,
    this.username,
    this.fullName,
    this.phoneNumber,
    this.email,
    required this.role,
    this.isVerified = false,
    required this.accountStatus,
    this.profileCompleted = false,
    this.hasActiveSubscription = false,
    this.createdAt,
    this.lastLoginAt,
  });

  factory ManagedUser.fromJson(Map<String, dynamic> json) {
    return ManagedUser(
      id: J.integer(json['id']),
      username: J.str(json['username']),
      fullName: J.str(json['full_name']),
      phoneNumber: J.str(json['phone_number']),
      email: J.str(json['email']),
      role: J.text(json['role'], 'customer'),
      isVerified: J.flag(json['is_verified']),
      accountStatus: J.text(json['account_status'], 'active'),
      profileCompleted: J.flag(json['profile_completed']),
      hasActiveSubscription: J.flag(json['active_subscription']),
      createdAt: J.parse(json['created_at']),
      lastLoginAt: J.parse(json['last_login_at']),
    );
  }

  String get displayName {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final handle = username?.trim();
    if (handle != null && handle.isNotEmpty) return handle;
    return phoneNumber ?? 'User $id';
  }

  bool get isSuspended => accountStatus == 'suspended';
}

/// `GET /admin/distance-rate`
class DistanceRateConfig {
  final double thresholdKm;
  final double ratePerKm;
  final double taxPercent;
  final double roundTripFactor;
  final bool isDefault;

  const DistanceRateConfig({
    required this.thresholdKm,
    required this.ratePerKm,
    required this.taxPercent,
    required this.roundTripFactor,
    this.isDefault = false,
  });

  factory DistanceRateConfig.fromJson(Map<String, dynamic> json) {
    return DistanceRateConfig(
      thresholdKm: J.dbl(json['threshold_km']),
      ratePerKm: J.dbl(json['rate_per_km']),
      taxPercent: J.dbl(json['tax_percent']),
      roundTripFactor: J.dbl(json['round_trip_factor'], 2),
      isDefault: J.flag(json['is_default']),
    );
  }
}

/// `GET /notifications`
class AppNotification {
  final int id;
  final String title;
  final String message;
  final String category;
  final String? referenceType;
  final int? referenceId;
  final bool isRead;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.category,
    this.referenceType,
    this.referenceId,
    this.isRead = false,
    this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: J.integer(json['id']),
      title: J.text(json['title']),
      message: J.text(json['message']),
      category: J.text(json['category']),
      referenceType: J.str(json['reference_type']),
      referenceId: J.intOrNull(json['reference_id']),
      isRead: J.flag(json['is_read']),
      createdAt: J.parse(json['created_at']),
    );
  }
}

/// `GET /notifications` wrapper carrying the unread badge count.
class NotificationFeed {
  final List<AppNotification> items;
  final int unreadCount;

  const NotificationFeed({this.items = const [], this.unreadCount = 0});

  factory NotificationFeed.fromJson(Map<String, dynamic> json) {
    return NotificationFeed(
      items: J
          .asMapList(json['notifications'])
          .map(AppNotification.fromJson)
          .toList(),
      unreadCount: J.integer(json['unread_count']),
    );
  }
}
