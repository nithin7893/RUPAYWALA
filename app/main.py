"""
Application entry point.

Responsibilities kept deliberately small and explicit:

* register every model so ``alembic``/``create_all`` see the full schema;
* configure CORS from the environment instead of a blanket ``*``;
* expose a health endpoint that reports which external integrations are ready;
* seed only the reference data the app cannot run without (pricing config and
  the service catalogue) - never demo users or fake orders.
"""

import logging

from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, Response
from starlette.middleware.trustedhost import TrustedHostMiddleware
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import (
    ALLOW_CREDENTIALS,
    CONTENT_SECURITY_POLICY,
    CORS_ALLOWED_ORIGINS,
    CORS_ALLOWED_ORIGIN_REGEX,
    DEBUG,
    EXPOSE_DOCS,
    GOOGLE_CLIENT_ID,
    HSTS_ENABLED,
    HSTS_MAX_AGE_SECONDS,
    HTTPS_REDIRECT_ENABLED,
    IS_PRODUCTION,
    TESTING,
    TRUSTED_HOSTS,
    UPI_ID,
    UPLOAD_DIR,
)
from app.database import Base, SessionLocal, engine, get_db
from app.utils.dependencies import get_current_user
from app.utils.proxy import is_trusted_peer

# ---------------------------------------------------------------------
# Models: importing them registers the tables on Base.metadata.
# ---------------------------------------------------------------------
from app.models import (  # noqa: F401
    branch,
    customer_profile,
    distance_rate_config,
    family_member,
    field_member,
    notification,
    otp_verification,
    payment,
    policy,
    policy_member,
    request_assignment,
    service_quote,
    service_request,
    service_type,
    subscription_plan,
    user,
    user_subscription,
    visit_ledger,
)

# ---------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------
from app.routes.admin_routes import router as admin_router
from app.routes.auth_routes import router as auth_router
from app.routes.document_routes import router as document_router
from app.routes.field_member_routes import router as field_member_router
from app.routes.notification_routes import router as notification_router
from app.routes.payment_routes import admin_router as payment_admin_router
from app.routes.payment_routes import router as payment_router
from app.routes.policy_routes import router as policy_router
from app.routes.profile_routes import router as profile_router
from app.routes.service_routes import router as service_router
from app.routes.subscription_routes import router as subscription_router

logging.basicConfig(
    level=logging.DEBUG if DEBUG else logging.INFO,
    format="%(asctime)s %(levelname)-8s %(name)s :: %(message)s",
)
logger = logging.getLogger("rupaywala")

app = FastAPI(
    title="Rupaywala API",
    description="Doorstep insurance service requests, subscriptions and payments.",
    version="2.0.0",
    docs_url="/docs" if EXPOSE_DOCS else None,
    redoc_url="/redoc" if EXPOSE_DOCS else None,
    openapi_url="/openapi.json" if EXPOSE_DOCS else None,
)

# Host allowlist. In development without explicit hosts, allow local hosts only.
_trusted_hosts = TRUSTED_HOSTS or (
    ["localhost", "127.0.0.1", "testserver"] if not IS_PRODUCTION else []
)
if _trusted_hosts:
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=_trusted_hosts)


@app.middleware("http")
async def enforce_https(request: Request, call_next):
    if HTTPS_REDIRECT_ENABLED:
        scheme = request.url.scheme
        if is_trusted_peer(request):
            forwarded_proto = request.headers.get("x-forwarded-proto", "")
            # Only honor forwarded proto as a signal; never trust it to bypass
            # HTTPS enforcement. Actual redirect decision uses request scheme.
            if forwarded_proto.lower() == "https":
                scheme = "https"
        if scheme != "https":
            url = request.url.replace(scheme="https")
            return JSONResponse(
                status_code=status.HTTP_307_TEMPORARY_REDIRECT,
                content={"detail": "HTTPS is required"},
                headers={"Location": str(url)},
            )
    return await call_next(request)


@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("Referrer-Policy", "no-referrer")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault(
        "Permissions-Policy",
        "camera=(), microphone=(), geolocation=(), payment=()",
    )
    if CONTENT_SECURITY_POLICY:
        response.headers.setdefault("Content-Security-Policy", CONTENT_SECURITY_POLICY)
    is_https = request.url.scheme == "https"
    if is_trusted_peer(request):
        is_https = is_https or request.headers.get("x-forwarded-proto", "").lower() == "https"
    if HSTS_ENABLED and is_https:
        response.headers.setdefault(
            "Strict-Transport-Security",
            f"max-age={HSTS_MAX_AGE_SECONDS}; includeSubDomains",
        )
    return response


app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ALLOWED_ORIGINS,
    allow_origin_regex=CORS_ALLOWED_ORIGIN_REGEX,
    allow_credentials=ALLOW_CREDENTIALS,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
)

# Uploaded documents are stored under UPLOAD_DIR. Public static serving is
# intentionally disabled; authenticated, authorized retrieval is exposed below.
_upload_path = Path(UPLOAD_DIR).resolve()
_upload_path.mkdir(parents=True, exist_ok=True)


def _resolve_upload_path(file_path: str) -> Path:
    if not file_path or file_path.startswith("/") or file_path.startswith("\\"):
        raise HTTPException(status_code=400, detail="Invalid document path")
    normalized = file_path.replace("\\", "/")
    if normalized.startswith("uploads/"):
        normalized = normalized[len("uploads/") :]
    parts = [p for p in normalized.split("/") if p]
    if not parts or any(p in {".", ".."} for p in parts):
        raise HTTPException(status_code=400, detail="Invalid document path")
    candidate = (_upload_path / Path(*parts)).resolve()
    try:
        candidate.relative_to(_upload_path)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid document path")
    return candidate


def _can_access_upload(db: Session, user, stored_path: str) -> bool:
    from app.models.field_member import FieldMember
    from app.models.request_assignment import RequestAssignment
    from app.models.service_request import ServiceRequest
    from app.models.user import UserRole

    request = (
        db.query(ServiceRequest)
        .filter(ServiceRequest.proof_image_url == stored_path)
        .first()
    )
    if request is None:
        return False
    if user.role == UserRole.admin:
        return True
    if request.user_id == user.id:
        return True
    if user.role == UserRole.field_member:
        member = db.query(FieldMember).filter(FieldMember.user_id == user.id).first()
        if member is None:
            return False
        assignment = (
            db.query(RequestAssignment.id)
            .filter(
                RequestAssignment.request_id == request.id,
                RequestAssignment.field_member_id == member.id,
            )
            .first()
        )
        return assignment is not None
    return False


@app.get("/uploads/{file_path:path}", tags=["Documents"])
def get_uploaded_document(
    file_path: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    normalized = file_path.replace("\\", "/")
    if normalized.startswith("uploads/"):
        normalized = normalized[len("uploads/") :]
    stored_path = normalized.lstrip("/")

    # Prefer DocumentRecord-backed authorization/gating when metadata exists.
    from app.models.document_record import DocumentRecord
    from app.services.document_service import DocumentService

    record = (
        db.query(DocumentRecord)
        .filter(DocumentRecord.storage_key == stored_path, DocumentRecord.deleted_at.is_(None))
        .first()
    )
    if record is not None:
        content, record = DocumentService.stream_content(db, document_id=record.id, user=current_user)
        return Response(
            content=content,
            media_type=record.mime_type,
            headers={"Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff"},
        )

    # Legacy local proof files (pre-5.6J) remain accessible with existing authz.
    candidate = _resolve_upload_path(stored_path)
    if not candidate.is_file():
        raise HTTPException(status_code=404, detail="Document not found")
    if not _can_access_upload(db, current_user, stored_path):
        raise HTTPException(status_code=404, detail="Document not found")
    return FileResponse(candidate, headers={"Cache-Control": "private, no-store"})


# ======================================================================
# Error handling - never leak a stack trace or an internal message
# ======================================================================
@app.exception_handler(IntegrityError)
def integrity_error_handler(request: Request, exc: IntegrityError) -> JSONResponse:
    logger.warning("Integrity error on %s: %s", request.url.path, exc.orig)
    return JSONResponse(
        status_code=status.HTTP_409_CONFLICT,
        content={"detail": "That record already exists or conflicts with existing data"},
    )


@app.exception_handler(Exception)
def unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.exception("Unhandled error on %s", request.url.path)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "Something went wrong. Please try again."},
    )


# ======================================================================
# Reference data
# ======================================================================
DEFAULT_SERVICE_TYPES = [
    ("claim_intimation", "Claim Intimation", "Register a claim with your insurer", "assignment", 1),
    ("policy_assistance", "Policy Assistance", "Help with policy wording, renewal and updates", "description", 2),
    ("inspection", "Inspection Support", "Doorstep inspection or risk assessment support", "search", 3),
    ("other", "Other Assistance", "Anything else you need help with", "support_agent", 4),
    ("claim_form_assistance", "Claim Form Assistance", "Help completing claim forms", "edit_document", 5),
    ("document_scanning", "Document Scanning", "Scan documents and provide digital copies", "document_scanner", 6),
    ("document_organization", "Document Organization", "Organize claim documents digitally", "folder_open", 7),
    ("claim_document_checklist", "Claim Document Checklist", "Prepare a claim-document checklist", "checklist", 8),
    ("document_verification", "Document Verification", "Review documents and identify missing items", "fact_check", 9),
    ("online_submission", "Online Submission", "Assist with online document submission", "upload_file", 10),
]


def seed_reference_data(db: Session) -> None:
    """Insert the rows the app needs to function. Safe to run repeatedly."""
    from app.config import (
        DEFAULT_CHARGE_PER_KM,
        DEFAULT_DISTANCE_THRESHOLD_KM,
        DEFAULT_TAX_PERCENT,
        DISTANCE_ROUND_TRIP_FACTOR,
    )
    from app.models.distance_rate_config import DistanceRateConfig
    from app.models.service_type import ServiceType
    from app.services.plan_catalog import seed_subscription_plans

    for code, name, description, icon, order in DEFAULT_SERVICE_TYPES:
        if not db.query(ServiceType).filter(ServiceType.code == code).first():
            db.add(
                ServiceType(
                    code=code,
                    name=name,
                    description=description,
                    icon=icon,
                    sort_order=order,
                )
            )
            logger.info("Seeded service type %s", code)

    if not db.query(func.count(DistanceRateConfig.id)).scalar():
        db.add(
            DistanceRateConfig(
                threshold_km=DEFAULT_DISTANCE_THRESHOLD_KM,
                rate_per_km=DEFAULT_CHARGE_PER_KM,
                tax_percent=DEFAULT_TAX_PERCENT,
                round_trip_factor=DISTANCE_ROUND_TRIP_FACTOR,
            )
        )
        logger.info("Seeded the default distance pricing configuration")

    seed_subscription_plans(db)
    db.commit()


@app.on_event("startup")
def on_startup() -> None:
    # The test suite creates its own schema and seeds only the rows each test
    # needs. Skipping both here prevents repeated startup work from racing with
    # the test session that is dropping/recreating the schema.
    if TESTING:
        logger.info("Test mode: startup schema creation and seeding skipped")
        return

    # Alembic owns the schema in production; create_all keeps a fresh dev
    # database usable without a migration step.
    if DEBUG:
        Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        seed_reference_data(db)
    except Exception:  # pragma: no cover - never block startup on seeding
        db.rollback()
        logger.exception("Reference data seeding failed")
    finally:
        db.close()
    logger.info("Rupaywala API ready")


# ======================================================================
# Routers
# ======================================================================
app.include_router(auth_router)
app.include_router(profile_router)
app.include_router(policy_router)
app.include_router(subscription_router)
app.include_router(service_router)
app.include_router(payment_router)
app.include_router(admin_router)
app.include_router(payment_admin_router)
app.include_router(field_member_router)
app.include_router(notification_router)
app.include_router(document_router)


# ======================================================================
# Health / diagnostics
# ======================================================================
@app.get("/", tags=["Health"])
def root():
    return {
        "message": "Rupaywala API is running",
        "docs": "/docs",
        "health": "/health",
    }


@app.get("/health", tags=["Health"])
def health(db: Session = Depends(get_db)):
    from app.services import map_service as maps

    database_ok = True
    try:
        db.query(func.count(user.User.id)).scalar()
    except Exception:
        logger.exception("Database health check failed")
        database_ok = False

    return {
        "status": "ok" if database_ok else "degraded",
        "database": "connected" if database_ok else "unavailable",
        "integrations": {
            "maps": maps.map_service_status(),
            "google_sign_in": bool(GOOGLE_CLIENT_ID),
            "upi_payments": bool(UPI_ID),
        },
    }
