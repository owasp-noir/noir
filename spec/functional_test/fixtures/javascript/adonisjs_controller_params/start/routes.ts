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
