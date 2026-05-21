const { createYoga, createSchema } = require('graphql-yoga');

const typeDefs = `
  type Query {
    ping: String
  }
  type Mutation {
    publish(channel: String!, body: String!): Boolean
  }
`;

const yoga = createYoga({
  schema: createSchema({ typeDefs }),
});

module.exports = yoga;
