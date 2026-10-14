import rss from '@astrojs/rss';
import { getCollection } from 'astro:content';

export async function GET(context) {
  const posts = await getCollection('blog');
  return rss({ title: 'Blog', site: context.site, items: posts.map((p) => ({ link: `/blog/${p.slug}/` })) });
}
