import { json, type LoaderFunctionArgs, type ActionFunctionArgs } from "@remix-run/node";

export async function loader({ request }: LoaderFunctionArgs) {
    return json([]);
}

export async function action({ request }: ActionFunctionArgs) {
    const body = await request.json();
    return json(body);
}
