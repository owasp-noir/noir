import { NextResponse } from "next/server"

async function listReports() {
  const reports = await reportService.list()
  AuditLog.write("next:reports")
  return NextResponse.json(reports)
}

export {
  // read-only
  listReports as GET,
}
