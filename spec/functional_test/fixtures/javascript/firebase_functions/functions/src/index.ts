import { onRequest, onCall, HttpsError } from "firebase-functions/v2/https";
import type { HttpsFunction } from "firebase-functions/v2/https";

export const createOrder: HttpsFunction = onRequest({ region: "us-central1", cors: true }, async (req, res) => {
  const { item, quantity } = req.body;
  res.json({ item, quantity });
});

export const getProfile = onCall({ enforceAppCheck: true }, (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "login");
  return { uid: request.auth.uid };
});
