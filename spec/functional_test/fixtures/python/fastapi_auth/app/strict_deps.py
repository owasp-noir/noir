from fastapi import HTTPException


def load_account(current_user):
    if not current_user.is_admin:
        raise HTTPException(status_code=403, detail="Admins only")
    return current_user
