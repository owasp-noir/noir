import { buildConfig } from 'payload'
import { Posts } from './collections/Posts'
import { Users } from './collections/Users'
import { SiteSettings } from './globals/SiteSettings'

export default buildConfig({
  collections: [Posts, Users],
  globals: [SiteSettings],
  localization: { locales: ['en', 'ko'], defaultLocale: 'en' },
})
