import { createYoga, createSchema } from 'graphql-yoga';
import { createServer } from 'node:http';

const yoga = createYoga({
  schema: createSchema({
    typeDefs: /* GraphQL */ `
      type Query {
        hello: String
        user(id: ID!): User
      }
      type Mutation {
        signin(email: String!, password: String!): Token!
      }
      type Subscription {
        clock: String
      }
      type User { id: ID!, name: String }
      type Token { value: String! }
    `,
    resolvers: {
      Query: {
        hello: () => 'world',
        user: (_, { id }) => ({ id, name: 'demo' }),
      },
    },
  }),
});

createServer(yoga).listen(4000);
