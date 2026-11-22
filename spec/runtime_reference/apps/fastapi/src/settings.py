import os


class Settings:
    member_prefix = "/members"
    staff_mount = os.getenv("STAFF_MOUNT", "/staff")


settings = Settings()
