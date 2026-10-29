import type { HttpContext } from '@adonisjs/core/http'
export default class NotesController {
  async store({ request }: HttpContext) { return request.only(['title', 'body']) }
  async search({ request }: HttpContext) {
    const q = request.input('q')
    const page = request.qs().page
    return { q, page }
  }
  async destroy({ params }: HttpContext) { return params.id }
}
