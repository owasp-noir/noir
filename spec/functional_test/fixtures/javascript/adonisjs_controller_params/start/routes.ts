import router from '@adonisjs/core/services/router'
import { middleware } from '#start/kernel'
const NotesController = () => import('#controllers/notes_controller')

router
  .group(() => {
    router.post('/notes', [NotesController, 'store'])
    router.get('/notes/search', [NotesController, 'search'])
  })
  .prefix('/api')
  .use(middleware.auth())
router.delete('/notes/:id', [NotesController, 'destroy'])
router.put('/notes/inline', [() => import('#controllers/notes_controller'), 'store'])
router.get('/notes/compact', [NotesController, 'compact'])
router.get('/notes/preview', [NotesController, 'store'])
router.get('/inline-params', ({ request }) => {
  const example = "request.input('fake-inline')"
  let assigned;
  ({ assigned } = request.body());
  return request.input('real-inline')
})
router.post('/inline-params', ({ request }) => {
  let assigned;
  ({ assigned } = request.body());
  return request.input('real-inline')
})
