import type { ActionFunctionArgs } from "@remix-run/node";

export async function action({ request }: ActionFunctionArgs) {
    const data = await request.formData();
    return null;
}

export default function Login() {
    return <form />;
}
