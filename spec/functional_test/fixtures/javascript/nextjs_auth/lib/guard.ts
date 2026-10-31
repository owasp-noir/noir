import type { NextRequest } from "next/server";

export const validateCronRequest = (req: NextRequest) => {
  const apiKey = req.headers.get("authorization");
  if (![process.env.CRON_API_KEY, `Bearer ${process.env.CRON_SECRET}`].includes(`${apiKey}`)) {
    throw new HttpError({ statusCode: 401, message: "Unauthorized" });
  }
};

// Refuses a caller who IS signed in (a sign-up page): not a guard.
export function rejectSignedIn(session) {
  if (session) {
    throw new HttpError({ statusCode: 403, message: "Already signed in" });
  }
}
