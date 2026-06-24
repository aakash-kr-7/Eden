# ═══════════════════════════════════════════════════════════════════
# FILE: registry.py
# PURPOSE: Companion matching, pair assignment, and PartnerInstance resolution.
# CONTEXT: Personality registry layer of Eden.
# ═══════════════════════════════════════════════════════════════════

import json
from datetime import datetime, timezone
import logging

logger = logging.getLogger(__name__)

class PartnerInstance:
    def __init__(self, partner_row: dict):
        self.id = partner_row["id"]
        self.name = partner_row["name"]
        
        # parse json fields
        persona = partner_row.get("persona_json") or {}
        if isinstance(persona, str):
            try:
                persona = json.loads(persona)
            except Exception:
                persona = {}
        self.persona = persona
        
        voice = partner_row.get("voice_style") or partner_row.get("voice_style_json") or {}
        if isinstance(voice, str):
            try:
                voice = json.loads(voice)
            except Exception:
                voice = {}
        self.voice_style = voice
        
        # fallback details
        self.personality_traits = self.persona.get("personality_traits") or {}
        self.core_identity = self.persona.get("core_identity") or {}
        self.matching_profile = self.persona.get("matching_profile") or {}
        
        # raw row data for reference
        self.raw = partner_row

def get_partner_instance(user_id_or_partner_id: str) -> PartnerInstance | None:
    """
    Returns PartnerInstance wrapper for a user or partner ID.
    """
    from memory.store import db
    partner_row = db.get_partner(user_id_or_partner_id) or db.get_partner_by_id(user_id_or_partner_id)
    if partner_row:
        return PartnerInstance(partner_row)
    return None

def resolve_or_assign_primary_pair(user_id: str) -> dict | None:
    """
    Resolves or assigns the primary relationship pair for a user.
    """
    from memory.store import db
    pair = db.get_primary_pair(user_id)
    if pair:
        return pair
        
    # Check if partner already exists for user
    partner = db.get_partner(user_id)
    if partner:
        partner_id = partner["id"]
        pair_id = f"{user_id}::{partner_id}"
        # Create pair
        now = datetime.now(timezone.utc).isoformat()
        with db.get_connection() as conn:
            conn.execute(
                """
                INSERT OR REPLACE INTO relationship_pairs
                (id, user_id, partner_id, current_stage, closeness_score, trust_score, openness_score, comfort_score, rhythm_score, created_at)
                VALUES (?, ?, ?, 'new', 0.18, 0.18, 0.12, 0.14, 0.10, ?)
                """,
                (pair_id, user_id, partner_id, now)
            )
            conn.commit()
        return db.get_primary_pair(user_id)
    return None
