import router from '@adonisjs/core/services/router'

router.get('/custom-parser', ({ request }) => request.body().message)
