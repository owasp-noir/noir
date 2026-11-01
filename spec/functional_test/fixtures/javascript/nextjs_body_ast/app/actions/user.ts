"use server";

import { cookies } from "next/headers";
import { createUser } from "@/lib/users";

// An expression-bodied action sits above a braced one: the first `{` after
// it belongs to `login`.
export const currentId = async () =>
  (await cookies()).get("id")?.value;

export async function login(formData: FormData): Promise<{ ok: true }> {
  const email = formData.get("email");
  await createUser(email);
  return { ok: true };
}
