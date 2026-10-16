import { action } from "mobx";
import * as Sentry from "@sentry/react";
import { client } from "~/utils/ApiClient";

export default class AuthStore {
  @action
  async deleteUser(data: Record<string, unknown>) {
    try {
      await client.post(`/users.delete`, data);
    } catch (err) {
      Sentry.captureException(err);
    }
  }
}
