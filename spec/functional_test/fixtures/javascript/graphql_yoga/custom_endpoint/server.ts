import { createYoga, createSchema } from 'graphql-yoga';

export const yoga = createYoga({
  schema: createSchema({
    typeDefs: `
      type Query {
        products(category: String): [Product!]!
      }
      type Mutation {
        addToCart(productId: ID!, quantity: Int!): Boolean
      }
      type Product { id: ID!, name: String! }
    `,
  }),
  graphqlEndpoint: '/api/graphql',
});
