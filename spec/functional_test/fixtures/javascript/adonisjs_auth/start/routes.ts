import router from '@adonisjs/core/services/router'
import { middleware } from '#start/kernel'
const NotesController = () => import('#controllers/notes_controller')

router.get('/notes', [NotesController, 'index']).use(middleware.auth())
router.delete('/notes/:id', [NotesController, 'destroy']).use(middleware.auth())
router
  .group(() => {
    router.post('/notes', [NotesController, 'store'])
  })
  .prefix('/api')
  .use(middleware.auth())
router.get('/public', [NotesController, 'index'])

// soft auth and a guest-only page let anonymous callers in
router.get('/feed', [NotesController, 'index']).use(middleware.silentAuth())
router.get('/login', [NotesController, 'index']).use(middleware.guest())

// guarded by guard name and as one of several middleware
router.get('/admin', [NotesController, 'index']).use([middleware.auth({ guards: ['web'] }), middleware.admin()])

// a group without auth, nested inside a guarded group
router
  .group(() => {
    router.get('/me', [NotesController, 'index'])
    router
      .group(() => {
        router.get('/drafts', [NotesController, 'index'])
      })
      .prefix('/inner')
  })
  .prefix('/account')
  .use(middleware.auth())

router
  .group(() => {
    router.get('/open', [NotesController, 'index'])
  })
  .prefix('/v2')

// a resource: auth on every action, and on some actions only
router.resource('posts', NotesController).use('*', middleware.auth())
router.resource('drafts', NotesController).use(['store'], middleware.auth())
