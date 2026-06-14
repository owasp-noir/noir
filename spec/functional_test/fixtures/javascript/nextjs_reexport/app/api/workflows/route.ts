import { serve } from "@upstash/workflow/nextjs";

// Handler destructured from a factory call.
export const { POST } = serve(async (context) => {
  await context.run("step", () => ({}));
});
