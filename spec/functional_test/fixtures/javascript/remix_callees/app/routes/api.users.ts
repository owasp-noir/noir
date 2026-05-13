import { json, type LoaderFunctionArgs, type ActionFunctionArgs } from "@remix-run/node";

export async function loader({ request }: LoaderFunctionArgs) {
  const url = new URL(request.url);
  const page = url.searchParams.get("page");
  const users = await listUsers(page);
  AuditLog.write("remix:list");

  return json(serializeUsers(users));
}

export async function action({ request }: ActionFunctionArgs) {
  const body = await request.json();
  await serviceFactory().create(body);
  AuditLog.write("remix:create");

  return json({ ok: true });
}
