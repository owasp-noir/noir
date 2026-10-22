// Fresh ignores `[._]test.<ext>` files in routes/ by default.
export const handler = {
  GET() {
    return new Response("test only");
  },
};
