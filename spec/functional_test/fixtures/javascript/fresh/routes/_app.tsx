// Plumbing — should NOT register as a route.
import { AppProps } from "$fresh/server.ts";

export default function App({ Component }: AppProps) {
    return <Component />;
}
