import express from 'express';
import { initServer, createExpressEndpoints } from '@ts-rest/express';
import { contract } from './contract';

const app = express();
const s = initServer();

const router = s.router(contract, {
  getPost: async ({ params: { id } }) => ({ status: 200, body: { id, title: 'x' } }),
  createPost: async ({ body }) => ({ status: 201, body: { id: '1', title: body.title } }),
  updatePost: async () => ({ status: 200, body: { id: '1', title: 'x' } }),
  searchPosts: async () => ({ status: 200, body: [] }),
  deletePost: async () => ({ status: 204, body: undefined }),
  comments: { listComments: async () => ({ status: 200, body: [] }) },
  admin: { stats: async () => ({ status: 200, body: { count: 0 } }) },
});

createExpressEndpoints(contract, router, app);

app.listen(3000);
