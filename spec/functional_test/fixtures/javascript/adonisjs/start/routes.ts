import Route from '@ioc:Adonis/Core/Route'

Route.get('/', 'HomeController.index')
Route.get('/health', () => ({ ok: true }))

Route.group(() => {
    Route.get('/users', 'UsersController.index')
    Route.post('/users', 'UsersController.store')
    Route.get('/users/:id', 'UsersController.show')
    Route.put('/users/:id', 'UsersController.update')
    Route.delete('/users/:id', 'UsersController.destroy')

    Route.group(() => {
        Route.get('/posts', 'PostsController.index')
        Route.post('/posts', 'PostsController.store')
        Route.patch('/posts/:postId', 'PostsController.patch')
    }).prefix('/blog').middleware('auth')
}).prefix('/api/v1')

Route.resource('articles', 'ArticlesController').apiOnly()
Route.resource('tags', 'TagsController').only(['index', 'show'])

Route.any('/wildcard', 'WildcardController.handle')
