from typing import Annotated, Any

from fastapi import Depends

from deps import Anonymous, Authenticator, OrgGuard, User

_ItemsRead = Authenticator(
    required_scopes={"items:read"},
    allowed_subjects={User},
)
ItemsRead = Annotated[
    Any, Depends(_ItemsRead)
]

ItemsBrowse = Annotated[
    Any,
    Depends(
        Authenticator(
            required_scopes=set(),
            allowed_subjects={User, Anonymous},
        )
    ),
]

OrgAccess = Annotated[Any, Depends(OrgGuard(allowed_subjects={User}))]
