import NextAuth from "next-auth";

// No verb keys: an options object, still an all-methods handler.
export default NextAuth({
  providers: [],
});
