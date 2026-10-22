import { component$ } from "@builder.io/qwik";
import { routeAction$, Form } from "@builder.io/qwik-city";

export const useLogin = routeAction$(async (data, { cookie }) => {
  cookie.set("session", String(data.user));
  return { ok: true };
});

export default component$(() => {
  const login = useLogin();
  return <Form action={login}>login</Form>;
});
