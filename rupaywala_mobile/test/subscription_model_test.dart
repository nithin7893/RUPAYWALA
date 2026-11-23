import 'package:flutter_test/flutter_test.dart';

import 'package:rupaywala_app/core/models/customer_models.dart';

void main() {
  test('subscription plan reads database-backed entitlements', () {
    final plan = SubscriptionPlan.fromJson({
      'id': 5,
      'code': 'family',
      'plan_name': 'Family',
      'price': 1299,
      'visits_included': 5,
      'max_family_members': 5,
      'max_adult_members': 2,
      'max_child_members': 3,
      'document_verification': true,
      'online_submission': true,
      'document_storage': false,
      'features': ['5 shared home visits'],
    });

    expect(plan.name, 'Family');
    expect(plan.price, 1299);
    expect(plan.visitsIncluded, 5);
    expect(plan.maxFamilyMembers, 5);
    expect(plan.maxAdultMembers, 2);
    expect(plan.maxChildMembers, 3);
    expect(plan.documentVerification, isTrue);
    expect(plan.onlineSubmission, isTrue);
    expect(plan.documentStorage, isFalse);
    expect(plan.features, ['5 shared home visits']);
  });

  test('unconfigured Premium Family limits remain unset', () {
    final plan = SubscriptionPlan.fromJson({
      'id': 7,
      'code': 'premium_family',
      'plan_name': 'Premium Family',
      'price': 1999,
      'visits_included': 5,
      'max_family_members': null,
      'additional_visits': null,
      'features': [],
    });

    expect(plan.maxFamilyMembers, isNull);
    expect(plan.additionalVisits, isNull);
  });

  test('family membership response includes its configured type', () {
    final member = SubscriptionFamilyMember.fromJson({
      'id': 9,
      'member_name': 'Child One',
      'relationship': 'child',
      'member_type': 'child',
      'date_of_birth': '2015-03-01',
    });

    expect(member.memberName, 'Child One');
    expect(member.memberType, 'child');
    expect(member.relationship, 'child');
  });
}
