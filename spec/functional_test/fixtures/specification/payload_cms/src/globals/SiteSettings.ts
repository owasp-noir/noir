import type { GlobalConfig } from 'payload'

export const SiteSettings: GlobalConfig = {
  slug: 'site-settings',
  fields: [
    {
      name: 'siteName',
      type: 'text',
    },
    {
      name: 'maintenance',
      type: 'checkbox',
    },
  ],
}
