import logging
import json
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from memory.relationship_engine import RelationshipEngine
from memory.store import db, memory_store

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/profile")

class ProfileUpdate(BaseModel):
    display_name: Optional[str] = None
    communication_pace: Optional[str] = Field(None, pattern="^(gentle|balanced|frequent)$")
    emotional_depth_preference: Optional[str] = None

@router.get("/me")
async def get_my_profile(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    user = db.get_user(identity.uid)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    primary = db.get_primary_pair(identity.uid)
    partner_basics = {}
    if primary:
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
            "name": partner.get("name") or primary.get("companion_id", "").title(),
            "stage": primary.get("current_stage") or "new",
            "days_together": days_together,
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
        "partner": partner_basics
    }

@router.get("/relationship")
async def get_relationship_details(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    engine = RelationshipEngine()
    summary = await engine.get_relationship_summary(identity.uid)
    return summary

@router.patch("/me")
async def update_profile(
    payload: ProfileUpdate,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    if payload.display_name is not None:
        db.conn.execute(
            "UPDATE users SET display_name = ? WHERE id = ?",
            (payload.display_name, identity.uid)
        )
        
    if payload.communication_pace is not None:
        primary = db.get_primary_pair(identity.uid)
        if primary:
            db.conn.execute(
                "UPDATE relationship_pairs SET proactive_cadence = ? WHERE id = ?",
                (payload.communication_pace, primary["id"])
            )
            
    if payload.emotional_depth_preference is not None:
        user = db.get_user(identity.uid)
        if user:
            try:
                signals = json.loads(user.get("onboarding_signals") or "{}")
            except Exception:
                signals = {}
            signals["depth_preference"] = payload.emotional_depth_preference
            db.conn.execute(
                "UPDATE users SET onboarding_signals = ? WHERE id = ?",
                (json.dumps(signals), identity.uid)
            )
            
    user = db.get_user(identity.uid)
    primary = db.get_primary_pair(identity.uid)
    partner = db.get_partner(identity.uid) or {}
    stage = primary.get("current_stage") or "new" if primary else "new"
    
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
            "name": partner.get("name") or (primary.get("companion_id", "").title() if primary else "Companion"),
            "stage": stage
        }
    }

@router.get("/memories")
async def get_memories(
    type: Optional[str] = Query(None),
    sort: str = Query("recent"),  # salience | recent | recalled
    page: int = Query(1, ge=1),
    limit: int = Query(10, ge=1, le=100),
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    primary = db.get_primary_pair(identity.uid)
    if not primary:
        return {"memories": [], "total": 0, "page": page, "limit": limit}
    pair_id = primary["id"]
    
    query = "FROM memory_index WHERE pair_id = ? AND archived = 0"
    params = [pair_id]
    
    if type:
        query += " AND memory_type = ?"
        params.append(type)
        
    count_row = db.conn.execute(f"SELECT COUNT(*) as count {query}", params).fetchone()
    total = count_row["count"] if count_row else 0
    
    if sort == "salience":
        query += " ORDER BY salience DESC, id DESC"
    elif sort == "recalled":
        query += " ORDER BY last_recalled_at DESC, id DESC"
    else:  # recent
        query += " ORDER BY created_at DESC, id DESC"
        
    offset = (page - 1) * limit
    query += " LIMIT ? OFFSET ?"
    params.extend([limit, offset])
    
    rows = db.conn.execute(f"SELECT * {query}", params).fetchall()
    
    memories = []
    for r in rows:
        d = dict(r)
        if d.get("tags"):
            try:
                d["tags"] = json.loads(d["tags"])
            except Exception:
                d["tags"] = []
        else:
            d["tags"] = []
            
        d.pop("source_message_ids", None)
        d.pop("source_message_id", None)
        d.pop("decay_factor", None)
        d.pop("user_id", None)
        d.pop("pair_id", None)
        d.pop("companion_id", None)
        
        memories.append(d)
        
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
    primary = db.get_primary_pair(identity.uid)
    if not primary:
        raise HTTPException(status_code=404, detail="Relationship not found")
    pair_id = primary["id"]
    
    row = db.conn.execute(
        "SELECT id FROM memory_index WHERE pair_id = ? AND (chroma_id = ? OR id = ?)",
        (pair_id, memory_id, memory_id)
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Memory not found")
        
    await memory_store.delete(memory_id)
    return {"success": True, "deleted": True}

@router.post("/memories/{memory_id}/pin")
async def pin_vault_memory(
    memory_id: str,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    primary = db.get_primary_pair(identity.uid)
    if not primary:
        raise HTTPException(status_code=404, detail="Relationship not found")
    pair_id = primary["id"]
    
    row = db.conn.execute(
        "SELECT salience FROM memory_index WHERE pair_id = ? AND (chroma_id = ? OR id = ?)",
        (pair_id, memory_id, memory_id)
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Memory not found")
        
    current_salience = float(row["salience"] or 0.0)
    new_salience = max(current_salience, 0.85)
    
    if memory_id.isdigit():
        db.conn.execute(
            "UPDATE memory_index SET is_pinned = 1, salience = ? WHERE id = ?",
            (new_salience, int(memory_id))
        )
    else:
        db.conn.execute(
            "UPDATE memory_index SET is_pinned = 1, salience = ? WHERE chroma_id = ?",
            (new_salience, str(memory_id))
        )
        
    return {"success": True, "pinned": True, "salience": new_salience}
