import { createFileRoute } from '@tanstack/react-router'

// A flat route whose last segment happens to be `stories`: the file name
// carries `.stories.` but it is a served route, not a Storybook story.
export const Route = createFileRoute('/user/$userId/stories')({
  component: UserStories,
})

function UserStories() {
  return <div>Stories</div>
}
