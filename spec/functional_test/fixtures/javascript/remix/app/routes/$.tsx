import { json, type LoaderFunctionArgs } from "@remix-run/node";

export async function loader({ params }: LoaderFunctionArgs) {
    return json({ slug: params["*"] });
}

export default function Splat() {
    return <h1>Catch-all</h1>;
}
