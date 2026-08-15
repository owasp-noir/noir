import {get, post, param, requestBody} from '@loopback/rest';

export class UserController {
  @post('/users')
  async create(@requestBody() user: object): Promise<object> {
    await this.validationService.validate(user);
    const created = await this.userRepository.create(user);
    AuditLog.write('user.create', created);
    return this.presenter.user(created);
  }

  @get('/users/{id}')
  async findById(
    @param.path.string('id') id: string,
    @param.query.string('include') include?: string,
  ): Promise<object> {
    const found = await this.userRepository.findById(id);
    return buildProfile(found, include);
  }
}
