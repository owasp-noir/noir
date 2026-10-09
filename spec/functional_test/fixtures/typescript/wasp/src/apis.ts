import type { FooBar, UpdateProfile, Webhook } from "wasp/server/api";

export const fooBar: FooBar = (req, res, context) => {
  const { search } = req.query;
  res.json({ msg: `Hello, ${context.user ? "registered user" : "stranger"}!`, search });
};

export const updateProfile: UpdateProfile = async (req, res, context) => {
  const { displayName, bio } = req.body;
  const token = req.headers["x-profile-token"];
  await context.entities.User.update({ where: { id: Number(req.params.userId) }, data: { displayName, bio } });
  res.json({ ok: true, token });
};

export function webhook(req, res) {
  const signature = req.get("X-Signature");
  res.json({ received: req.body.event, signature });
}

export const fooMiddleware = (config) => config;
