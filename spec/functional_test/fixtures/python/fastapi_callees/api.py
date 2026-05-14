from fastapi import APIRouter
import db

api = APIRouter()


@api.get("/reports")
def list_reports():
    rows = db.fetch_report()
    return rows
