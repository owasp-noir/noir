import axios from 'axios';
import { createYoga, createSchema } from 'graphql-yoga';
import { describe, it } from 'vitest';

describe('yoga', () => {
  it('serves a schema', async () => {
    const yoga = createYoga({
      schema: createSchema({
        typeDefs: /* GraphQL */ `
          type Query {
            phantom: String
          }
        `,
        resolvers: { Query: { phantom: () => 'x' } },
      }),
    });
    await axios.get('http://localhost/graphql');
  });
});
