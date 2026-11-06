import type { NextApiRequest } from "next"

// Redeem a token the caller was mailed: anyone holding the link may call.
export async function redeemEmailToken(token: string) {
  return token.length > 8 ? { email: "a@b.c" } : null
}

export async function lookupResetToken(token: string) {
  return token ? { userId: 1 } : null
}

// Mints a token: says nothing about who calls.
export async function generateToken({ req }: { req: NextApiRequest }) {
  return req.headers.host ? "t" : "none"
}

// next-auth's shape: null, not a message, when there is no token.
export async function readJwt({ req }: { req: NextApiRequest }) {
  return req.headers.authorization ? { sub: "1" } : null
}
