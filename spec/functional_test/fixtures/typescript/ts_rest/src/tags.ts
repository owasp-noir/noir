import { initContract } from '@ts-rest/core';
import { z } from 'zod';

const c = initContract();
const BASE = '/v2';
const TagMeta = z.object({ color: z.string() });

export const tagsContract = c.router({
  createTag: {
    method: 'POST',
    path: `${BASE}/tags`,
    body: z.object({ name: z.string() }).merge(TagMeta),
    responses: { 201: z.any() },
  },
});
