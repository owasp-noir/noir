import typing_extensions
from fastapi import Depends, Header


def tenant(x_tenant_id: str = Header(...)):
    return x_tenant_id


Tenant = typing_extensions.Annotated[str, Depends(tenant)]
