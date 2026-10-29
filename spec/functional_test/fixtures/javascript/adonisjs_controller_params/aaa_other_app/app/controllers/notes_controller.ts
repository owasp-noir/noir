import type { HttpContext } from '@adonisjs/core/http'

// Same basename as the app under test. Its fields must not win.
export default class NotesController {
  async store({ request }: HttpContext) { return request.only(['secret']) }
  async search({ request }: HttpContext) { return request.input('secret') }
  async destroy({ params }: HttpContext) { return params.id }
}
