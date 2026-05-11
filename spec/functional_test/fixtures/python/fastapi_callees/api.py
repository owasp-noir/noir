from fastapi import APIRouter
from db import fetch_report

api = APIRouter()


@api.get("/reports")
def list_reports():
    rows = fetch_report()
    return rows
