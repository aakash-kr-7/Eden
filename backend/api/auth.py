from fastapi import APIRouter, Depends
from auth.firebase import get_authenticated_identity, User

router = APIRouter()

@router.get("/me")
async def get_me(identity: User = Depends(get_authenticated_identity)):
    """Retrieve current authenticated user details."""
    return {
        "user_id": identity.user_id,
        "email": identity.email
    }
