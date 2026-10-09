import { page, route, type Auth, type Spec } from "@wasp.sh/spec";

import { LoginPage } from "./LoginPage" with { type: "ref" };

export const authConfig: Auth = {
  userEntity: "User",
  methods: {
    email: {
      fromField: { name: "Todo", email: "todo@example.com" },
      emailVerification: { clientRoute: "EmailVerificationRoute" },
      passwordReset: { clientRoute: "PasswordResetRoute" },
    },
    gitHub: {},
  },
  onAuthFailedRedirectTo: "/login",
};

export const authSpec: Spec = [
  route("LoginRoute", "/login", page(LoginPage)),
];
