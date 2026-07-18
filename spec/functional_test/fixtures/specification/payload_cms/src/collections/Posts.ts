import type { CollectionConfig } from 'payload'

export const Posts: CollectionConfig = {
  slug: 'posts',
  versions: {
    drafts: true,
  },
  fields: [
    {
      name: 'title',
      type: 'text',
      required: true,
    },
    {
      type: 'row',
      fields: [
        {
          name: 'views',
          type: 'number',
        },
        {
          name: 'featured',
          type: 'checkbox',
        },
      ],
    },
    {
      name: 'meta',
      type: 'group',
      fields: [
        {
          name: 'description',
          type: 'textarea',
        },
      ],
    },
    {
      name: 'publishedAt',
      type: 'date',
    },
  ],
  endpoints: [
    {
      path: '/:id/tracking',
      method: 'get',
      handler: async (req) => Response.json({ ok: true }),
    },
  ],
}
