import type { Route } from "./+types/user";

export async function loader({ params }: Route.LoaderArgs) {
  return Response.json({ id: params.id });
}

export async function action({ params, request }: Route.ActionArgs) {
  return Response.json({ id: params.id, method: request.method });
}
