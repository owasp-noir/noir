import { NextResponse, type NextRequest } from "next/server";
import { getServerSession } from "next-auth";

export const validateCronRequest = (req: NextRequest) => {
  const apiKey = req.headers.get("authorization");
  if (![process.env.CRON_API_KEY, `Bearer ${process.env.CRON_SECRET}`].includes(`${apiKey}`)) {
    throw new HttpError({ statusCode: 401, message: "Unauthorized" });
  }
};

// Returns its refusal as a value: guards only a caller that hands it on.
export async function checkSession() {
  const session = await getServerSession();
  if (!session) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  return null;
}

// Refuses a caller who IS signed in (a sign-up page): not a guard.
export function rejectSignedIn(session) {
  if (session) {
    throw new HttpError({ statusCode: 403, message: "Already signed in" });
  }
}
