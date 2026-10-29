from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class BranchCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=200)
    address: str = Field(..., min_length=5, max_length=1000)
    contact_number: Optional[str] = Field(default=None, max_length=20)
    city: Optional[str] = Field(default=None, max_length=100)
    state: Optional[str] = Field(default=None, max_length=100)
    pincode: Optional[str] = Field(default=None, max_length=10)
    # Optional explicit coordinates; when omitted the address is geocoded.
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)


class BranchUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=2, max_length=200)
    address: Optional[str] = Field(default=None, min_length=5, max_length=1000)
    contact_number: Optional[str] = Field(default=None, max_length=20)
    city: Optional[str] = Field(default=None, max_length=100)
    state: Optional[str] = Field(default=None, max_length=100)
    pincode: Optional[str] = Field(default=None, max_length=10)
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)
    is_active: Optional[bool] = None


class BranchResponse(BaseModel):
    id: int
    name: str
    address: str
    latitude: float
    longitude: float
    contact_number: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    pincode: Optional[str] = None
    is_active: bool = True
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class BranchWithDistance(BaseModel):
    id: int
    name: str
    address: str
    latitude: float
    longitude: float
    contact_number: Optional[str] = None
    distance_km: float
    duration_minutes: float = 0.0
    excess_distance_km: float = 0.0
    extra_charge: float = 0.0
    tax_amount: float = 0.0
    total_amount: float = 0.0
    within_threshold: bool = True
