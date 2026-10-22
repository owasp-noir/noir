import { initContract } from '@ts-rest/core';
import { z } from 'zod';

const c = initContract();

const PostSchema = z.object({
  id: z.string(),
  title: z.string(),
});

const UpdatePostBody = z.object({
  title: z.string().optional(),
  content: z.string(),
}).strict();

// Referenced by name below, so it inherits the outer `/api` prefix.
const commentsContract = c.router(
  {
    listComments: {
      method: 'GET',
      path: '/posts/:postId/comments',
      query: z.object({ cursor: z.string().optional() }),
      responses: { 200: z.array(z.any()) },
    },
  },
  /* options */ { pathPrefix: '/v1' },
);

export const contract = c.router(
  {
    getPost: {
      method: 'GET',
      path: '/posts/:id',
      responses: { 200: PostSchema },
      summary: 'Get a post by id',
    },
    createPost: {
      method: 'POST',
      path: '/posts',
      body: z.object({ title: z.string() }),
      responses: { 201: PostSchema },
    },
    updatePost: {
      method: 'PATCH',
      path: '/posts/:id',
      body: UpdatePostBody,
      headers: z.object({ 'x-api-key': z.string() }),
      responses: { 200: PostSchema },
    },
    searchPosts: {
      method: 'GET',
      path: `/posts/search`,
      query: z.object({ q: z.string(), take: z.number() }),
      responses: { 200: z.array(PostSchema) },
    },
    deletePost: {
      method: 'DELETE',
      path: '/posts/:id',
      body: c.noBody(),
      responses: { 204: c.noBody() },
    },
    comments: commentsContract,
    admin: c.router(
      {
        stats: { method: 'GET', path: '/stats', responses: { 200: c.type<{ count: number }>() } },
      },
      { pathPrefix: '/admin' },
    ),
  },
  { pathPrefix: '/api', strictStatusCodes: true },
);
