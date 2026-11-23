import 'api_client.dart';
import 'token_store.dart';
import 'repositories/admin_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/customer_repository.dart';
import 'repositories/field_member_repository.dart';
import 'repositories/notification_repository.dart';
import 'repositories/payment_repository.dart';
import 'repositories/service_repository.dart';
import 'repositories/subscription_repository.dart';

/// Single entry point for every repository, so screens depend on one injected
/// object instead of seven.
class Api {
  factory Api({ApiClient? client, TokenStore? tokenStore}) {
    final sharedTokens = tokenStore ?? TokenStore();
    final sharedClient = client ?? ApiClient(tokenStore: sharedTokens);
    return Api._(client: sharedClient, tokens: sharedTokens);
  }

  Api._({required this.client, required this.tokens}) {
    auth = AuthRepository(client);
    customer = CustomerRepository(client);
    service = ServiceRepository(client);
    subscriptions = SubscriptionRepository(client);
    payments = PaymentRepository(client);
    admin = AdminRepository(client);
    fieldMember = FieldMemberRepository(client);
    notifications = NotificationRepository(client);
  }

  final ApiClient client;
  final TokenStore tokens;

  late final AuthRepository auth;
  late final CustomerRepository customer;
  late final ServiceRepository service;
  late final SubscriptionRepository subscriptions;
  late final PaymentRepository payments;
  late final AdminRepository admin;
  late final FieldMemberRepository fieldMember;
  late final NotificationRepository notifications;
}
