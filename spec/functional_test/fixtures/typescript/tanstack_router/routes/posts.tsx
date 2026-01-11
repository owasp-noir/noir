import { createFileRoute } from '@tanstack/react-router'
import { z } from 'zod'

export const Route = createFileRoute('/posts')({
  validateSearch: z.object({
    page: z.number().optional(),
    filter: z.string().optional(),
  }),
  component: PostsComponent,
})

function PostsComponent() {
  const { page, filter } = Route.useSearch()
  return (
    <div>
      <h1>Posts</h1>
      <p>Page: {page}</p>
      <p>Filter: {filter}</p>
    </div>
  )
}
