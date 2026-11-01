import { createFileRoute } from "@tanstack/react-router";
import { fetchPosts, PostsPage } from "../lib/posts";

export const Route = createFileRoute("/posts")({
  component: PostsPage,
  // a return type with an object literal type: `async` is not a reference
  loader: async (): Promise<{ posts: string[] }> => {
    return fetchPosts(`${ { a: 1 }.a }`);
  },
});
