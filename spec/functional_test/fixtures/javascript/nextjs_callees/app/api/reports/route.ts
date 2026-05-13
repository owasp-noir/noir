import { NextResponse } from "next/server"

async function listReports() {
  const reports = await reportService.list()
  AuditLog.write("next:reports")
  return NextResponse.json(reports)
}

export { listReports as GET }
