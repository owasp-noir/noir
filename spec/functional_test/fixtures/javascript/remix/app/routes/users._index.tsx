import { json, type LoaderFunctionArgs } from "@remix-run/node";

export async function loader({ request }: LoaderFunctionArgs) {
    return json([]);
}

export default function Users() {
    return <ul />;
}
