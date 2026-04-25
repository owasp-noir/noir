import { json, type LoaderFunctionArgs, type ActionFunctionArgs } from "@remix-run/node";

export async function loader({ params }: LoaderFunctionArgs) {
    return json({ id: params.id });
}

export async function action({ request, params }: ActionFunctionArgs) {
    if (request.method === "DELETE") {
        return json({ deleted: params.id });
    }
    const data = await request.formData();
    return json({ updated: params.id });
}

export default function User() {
    return <h1>user</h1>;
}
