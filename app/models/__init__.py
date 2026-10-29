"""Model package.

Importing this package registers every table on ``app.database.Base.metadata``.
Alembic, ``create_all`` and the test-suite all rely on that, so the imports are
kept explicit here instead of relying on every caller to remember the list.
"""

from app.models.branch import Branch
from app.models.customer_profile import CustomerProfile
from app.models.distance_rate_config import DistanceRateConfig
from app.models.family_member import FamilyMember
from app.models.field_member import FieldMember, FieldMemberApprovalStatus
from app.models.notification import Notification, NotificationCategory
from app.models.otp_verification import OTPPurpose, OTPVerification
from app.models.payment import Payment, PaymentStatus, PaymentType
from app.models.policy import Policy
from app.models.policy_member import PolicyMember
from app.models.request_assignment import AssignmentStatus, RequestAssignment
from app.models.service_request import RequestStatus, ServiceRequest
from app.models.service_type import ServiceType
from app.models.subscription_plan import SubscriptionPlan
from app.models.subscription_family_member import SubscriptionFamilyMember
from app.models.user import AccountStatus, AuthProvider, User, UserRole
from app.models.user_subscription import SubscriptionStatus, UserSubscription
from app.models.visit_ledger import VisitEntryType, VisitLedgerEntry

__all__ = [
    "AccountStatus",
    "AssignmentStatus",
    "AuthProvider",
    "Branch",
    "CustomerProfile",
    "DistanceRateConfig",
    "FamilyMember",
    "FieldMember",
    "FieldMemberApprovalStatus",
    "Notification",
    "NotificationCategory",
    "OTPPurpose",
    "OTPVerification",
    "Payment",
    "PaymentStatus",
    "PaymentType",
    "Policy",
    "PolicyMember",
    "RequestAssignment",
    "RequestStatus",
    "ServiceRequest",
    "ServiceType",
    "SubscriptionPlan",
    "SubscriptionFamilyMember",
    "SubscriptionStatus",
    "User",
    "UserRole",
    "UserSubscription",
    "VisitEntryType",
    "VisitLedgerEntry",
]
