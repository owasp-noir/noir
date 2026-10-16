import { createFileRoute } from '@tanstack/react-router'

// A Storybook story that mounts a router to render the page; not an app route.
export const Route = createFileRoute('/phantom-story')({
  component: StoryComponent,
})

function StoryComponent() {
  return <div>Story</div>
}

export default { title: 'Admin' }
