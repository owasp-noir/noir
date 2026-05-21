// Apollo Server v4 standalone server with inline gql typeDefs.
import { ApolloServer } from '@apollo/server';
import { startStandaloneServer } from '@apollo/server/standalone';
import gql from 'graphql-tag';

const typeDefs = gql`
  type Query {
    "Look up a single user by id."
    user(id: ID!): User
    users(limit: Int = 10, offset: Int = 0): [User!]!
  }

  type Mutation {
    createUser(input: UserInput!): User
    deleteUser(id: ID!): Boolean @auth(role: "admin")
  }

  type Subscription {
    userAdded: User
  }

  input UserInput {
    name: String!
    email: String!
  }

  type User {
    id: ID!
    name: String
    email: String
  }
`;

const resolvers = {
  Query: {
    user: (_: unknown, args: { id: string }) => null,
    users: () => [],
  },
  Mutation: {
    createUser: () => null,
    deleteUser: () => true,
  },
};

const server = new ApolloServer({ typeDefs, resolvers });

const { url } = await startStandaloneServer(server, {
  listen: { port: 4000 },
});

console.log(`Apollo Server ready at ${url}`);
