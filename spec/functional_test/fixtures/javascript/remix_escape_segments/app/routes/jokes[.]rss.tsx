import { type LoaderFunctionArgs } from "@remix-run/node";

// `[.]` escapes a literal dot in the Remix flat-file name, so the URL is
// `/jokes.rss` — the `.` must NOT split the leaf into two segments.
export const loader = async ({ request }: LoaderFunctionArgs) => {
  return new Response("<rss></rss>", {
    headers: { "Content-Type": "application/xml" },
  });
};
