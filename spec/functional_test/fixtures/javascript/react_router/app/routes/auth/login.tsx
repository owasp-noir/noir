import { redirect } from "react-router";
import type { Route } from "./+types/login";

export async function action({ request }: Route.ActionArgs) {
  await request.formData();
  return redirect("/");
}

export default function Login() {
  return <form method="post" />;
}
