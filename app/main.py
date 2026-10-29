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

from fastapi import Depends, FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import (
    ALLOW_CREDENTIALS,
    CORS_ALLOWED_ORIGINS,
    DEBUG,
    GOOGLE_CLIENT_ID,
    UPI_ID,
)
from app.database import Base, SessionLocal, engine, get_db

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
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ALLOWED_ORIGINS,
    allow_credentials=ALLOW_CREDENTIALS,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
)


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
