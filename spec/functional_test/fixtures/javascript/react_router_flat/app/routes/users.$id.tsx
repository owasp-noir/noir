import type { Route } from "./+types/users.$id";

export async function loader({ params }: Route.LoaderArgs) {
  return { id: params.id };
}

export async function action({ params }: Route.ActionArgs) {
  return { id: params.id };
}

export default function User() {
  return <h1>User</h1>;
}
