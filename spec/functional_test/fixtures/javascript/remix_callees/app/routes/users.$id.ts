import { json, type LoaderFunctionArgs, type ActionFunctionArgs } from "@remix-run/node";

export const loader = async ({ params }: LoaderFunctionArgs) => {
  const user = await loadUser(params.id);
  return json(serializeUser(user));
};

const mutateUser = async ({ params, request }: ActionFunctionArgs) => {
  const body = await request.formData();
  await updateUser(params.id, body);
  return json({ ok: true });
};

export { mutateUser as action };
