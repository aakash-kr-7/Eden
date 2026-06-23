import logging
import json
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from auth.firebase import AuthenticatedIdentity, get_authenticated_identity

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/profile")

db = None
memory_store = None
RelationshipEngine = None

class ProfileUpdate(BaseModel):
    display_name: Optional[str] = None
    communication_pace: Optional[str] = Field(None, pattern="^(gentle|balanced|frequent)$")
    emotional_depth_preference: Optional[str] = None
    allow_proactive_messages: Optional[bool] = None
    allow_push_notifications: Optional[bool] = None

@router.get("/me")
async def get_my_profile(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    user = db.get_user(identity.uid) if db else None
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    preferences = db.get_or_create_user_preferences(identity.uid) if db else {}
    primary = db.get_primary_pair(identity.uid) if db else None
    partner_basics = {}
    if primary and db:
        partner = db.get_partner(identity.uid) or {}
        introduced_str = primary.get("introduced_at") or primary.get("created_at")
        days_together = 1
        if introduced_str:
            try:
                intro_dt = datetime.fromisoformat(str(introduced_str).split(".")[0])
                days_together = max(1, (datetime.utcnow() - intro_dt).days)
            except Exception:
                pass
        
        partner_basics = {
            "name": partner.get("name") or primary.get("partner_id", "").title(),
            "stage": primary.get("current_stage") or "new",
            "days_together": days_together,
            "memory_count": primary.get("memory_count") or 0,
        }
    
    return {
        "user": {
            "id": user["id"],
            "display_name": user.get("display_name"),
            "email": user.get("email"),
            "preferred_name": user.get("preferred_name"),
            "timezone": user.get("timezone"),
            "onboarding_completed": bool(user.get("onboarding_completed", 0)),
        },
        "partner": partner_basics,
        "preferences": preferences,
    }

@router.get("/relationship")
async def get_relationship_details(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    if not RelationshipEngine:
        return {}
    engine = RelationshipEngine()
    summary = await engine.get_relationship_summary(identity.uid)
    return summary

@router.patch("/me")
async def update_profile(
    payload: ProfileUpdate,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    if not db:
        return {"success": False}
    if payload.display_name is not None:
        db.update_user_display_name(identity.uid, payload.display_name)
        
    if payload.communication_pace is not None:
        primary = db.get_primary_pair(identity.uid)
        if primary:
            db.update_pair_proactive_cadence(primary["id"], payload.communication_pace)
            
    if payload.emotional_depth_preference is not None:
        db.update_user_onboarding_depth_preference(identity.uid, payload.emotional_depth_preference)
            
    prefs_to_update = {}
    if payload.allow_proactive_messages is not None:
        prefs_to_update["allow_proactive_messages"] = 1 if payload.allow_proactive_messages else 0
    if payload.allow_push_notifications is not None:
        prefs_to_update["allow_push_notifications"] = 1 if payload.allow_push_notifications else 0
        
    if prefs_to_update:
        db.update_user_preferences(identity.uid, **prefs_to_update)

    user = db.get_user(identity.uid)
    primary = db.get_primary_pair(identity.uid)
    partner = db.get_partner(identity.uid) or {}
    stage = primary.get("current_stage") or "new" if primary else "new"
    preferences = db.get_or_create_user_preferences(identity.uid)
    
    return {
        "success": True,
        "user": {
            "id": user["id"],
            "display_name": user.get("display_name"),
            "email": user.get("email"),
            "preferred_name": user.get("preferred_name"),
            "timezone": user.get("timezone"),
        },
        "partner": {
            "name": partner.get("name") or (primary.get("partner_id", "").title() if primary else "Partner"),
            "stage": stage
        },
        "preferences": preferences,
    }

@router.get("/memories")
async def get_memories(
    type: Optional[str] = Query(None),
    sort: str = Query("recent"),  # salience | recent | recalled
    page: int = Query(1, ge=1),
    limit: int = Query(10, ge=1, le=100),
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    if not db:
        return {"memories": [], "total": 0, "page": page, "limit": limit}
    primary = db.get_primary_pair(identity.uid)
    if not primary:
        return {"memories": [], "total": 0, "page": page, "limit": limit}
    pair_id = primary["id"]
    
    memories, total = db.get_memories_paginated(
        pair_id=pair_id,
        memory_type=type,
        sort=sort,
        page=page,
        limit=limit
    )
    
    return {
        "memories": memories,
        "total": total,
        "page": page,
        "limit": limit
    }

@router.delete("/memories/{memory_id}")
async def delete_vault_memory(
    memory_id: str,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    if not db or not memory_store:
        return {"success": False}
    primary = db.get_primary_pair(identity.uid)
    if not primary:
        raise HTTPException(status_code=404, detail="Relationship not found")
    pair_id = primary["id"]
    
    if not db.verify_memory_ownership(pair_id, memory_id):
        raise HTTPException(status_code=404, detail="Memory not found")
        
    await memory_store.delete(memory_id)
    return {"success": True, "deleted": True}

@router.post("/memories/{memory_id}/pin")
async def pin_vault_memory(
    memory_id: str,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    if not db or not memory_store:
        return {"success": False}
    primary = db.get_primary_pair(identity.uid)
    if not primary:
        raise HTTPException(status_code=404, detail="Relationship not found")
    pair_id = primary["id"]
    
    if not db.verify_memory_ownership(pair_id, memory_id):
        raise HTTPException(status_code=404, detail="Memory not found")
        
    new_salience = await memory_store.pin_and_boost_salience(memory_id)
        
    return {"success": True, "pinned": True, "salience": new_salience}

@router.delete("/memories")
async def delete_all_vault_memories(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    if not db:
        return {"success": False}
    primary = db.get_primary_pair(identity.uid)
    if not primary:
        raise HTTPException(status_code=404, detail="Relationship not found")
    pair_id = primary["id"]
    
    db.clear_all_memories(pair_id)
    return {"success": True, "deleted_all": True}

@router.delete("/me")
async def delete_my_profile(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    if not db:
        return {"success": False}
    db.delete_user(identity.uid)
    return {"success": True, "deleted_user": True}
