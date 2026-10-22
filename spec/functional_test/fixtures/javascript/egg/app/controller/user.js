'use strict';

const { Controller } = require('egg');

class UserController extends Controller {
  async show() {
    const { ctx } = this;
    const fields = ctx.query.fields;
    ctx.body = await ctx.service.user.find(ctx.params.id, fields);
  }

  async login() {
    const { ctx } = this;
    const { username, password } = ctx.request.body;
    const csrf = ctx.cookies.get('csrfToken');
    ctx.body = await ctx.service.user.login(username, password, csrf);
  }

  async destroy() {
    const token = this.ctx.get('x-admin-token');
    await this.ctx.service.user.remove(this.ctx.params.id, token);
  }
}

module.exports = UserController;
