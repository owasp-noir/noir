import type { Route } from "./+types/users";

export async function loader({}: Route.LoaderArgs) {
  return Response.json([]);
}
