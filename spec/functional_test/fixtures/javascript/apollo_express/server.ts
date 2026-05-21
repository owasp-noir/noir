// Apollo Server v4 mounted as Express middleware at a custom path.
// The analyzer should pick `/api/graphql` from the `app.use(...)` call.
import express from 'express';
import { ApolloServer } from '@apollo/server';
import { expressMiddleware } from '@apollo/server/express4';

const typeDefs = `#graphql
  type Query {
    ping: String
    products(category: String): [Product!]!
  }

  type Mutation {
    addToCart(productId: ID!, quantity: Int = 1): Boolean
  }

  type Product {
    id: ID!
    name: String!
    price: Float!
  }
`;

const server = new ApolloServer({ typeDefs, resolvers: {} });
await server.start();

const app = express();
app.use(express.json());
app.use('/api/graphql', expressMiddleware(server));

app.listen(4000);
