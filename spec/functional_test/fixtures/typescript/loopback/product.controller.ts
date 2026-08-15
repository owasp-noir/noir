import {
  get,
  post,
  put,
  patch,
  del,
  param,
  requestBody,
  operation,
} from '@loopback/rest';
import {authenticate} from '@loopback/authentication';
import {authorize} from '@loopback/authorization';

export class ProductController {
  @get('/products')
  async find(
    @param.query.number('limit') limit?: number,
    @param.query.string('filter') filter?: string,
  ): Promise<object[]> {
    return [];
  }

  @get('/products/{id}')
  async findById(@param.path.string('id') id: string): Promise<object> {
    return {};
  }

  @post('/products', {
    responses: {
      '200': {description: 'Product model instance'},
    },
  })
  @authenticate('jwt')
  @authorize({allowedRoles: ['admin']})
  async create(@requestBody() product: object): Promise<object> {
    return {};
  }

  @put('/products/{id}')
  @authenticate('jwt')
  async replaceById(
    @param.path.string('id') id: string,
    @requestBody() product: object,
  ): Promise<void> {}

  @patch('/products/{id}')
  async updateById(
    @param.path.string('id') id: string,
    @requestBody() product: object,
  ): Promise<void> {}

  @del('/products/{id}')
  @authenticate('jwt')
  @authorize({allowedRoles: ['admin']})
  async deleteById(@param.path.string('id') id: string): Promise<void> {}

  // No explicit `@param.path` decorator here — `id` should still be
  // picked up from the `{id}` URL placeholder fallback.
  @get('/products/{id}/reviews')
  async reviews(
    @param.header.string('x-api-key') apiKey: string,
  ): Promise<object[]> {
    return [];
  }

  @get('/products/search')
  async search(
    @param.array('tags', 'query', {type: 'string'}) tags?: string[],
  ): Promise<object[]> {
    return [];
  }

  @operation('get', '/products/count', {
    responses: {'200': {description: 'count'}},
  })
  async count(): Promise<object> {
    return {};
  }
}
