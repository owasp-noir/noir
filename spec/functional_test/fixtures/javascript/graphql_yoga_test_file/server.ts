import { createYoga, createSchema } from 'graphql-yoga';
import { createServer } from 'node:http';

const yoga = createYoga({
  schema: createSchema({
    typeDefs: /* GraphQL */ `
      type Query {
        hello: String
      }
    `,
    resolvers: { Query: { hello: () => 'world' } },
  }),
});

createServer(yoga).listen(4000);
