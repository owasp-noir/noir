import NextAuth from "next-auth";

const authOptions = {
  providers: [],
};

// A config object is not a handler: the row points at the export.
export default NextAuth(authOptions);
