// A GraphQL BFF: no http-server import, but it resolves fields by calling an
// upstream API with node-fetch. That import must not make the file look like
// a test stub.
import { createServer } from 'node:http';
import { createYoga, createSchema } from 'graphql-yoga';
import fetch from 'node-fetch';

const yoga = createYoga({
  schema: createSchema({
    typeDefs: /* GraphQL */ `
      type Query {
        hello: String
      }
    `,
    resolvers: {
      Query: {
        hello: async () => (await fetch('https://api.example.com/hello')).text(),
      },
    },
  }),
});

createServer(yoga).listen(4000);
