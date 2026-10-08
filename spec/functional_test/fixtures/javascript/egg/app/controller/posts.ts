import { Controller } from 'egg';

export default class PostsController extends Controller {
  public async index(): Promise<{ list: string[] }> {
    const { ctx } = this;
    ctx.body = await ctx.service.post.list(ctx.query.page);
    return ctx.body;
  }

  public async show(): Promise<void> {
    const { ctx } = this;
    ctx.body = await ctx.service.post.find(ctx.params.id);
  }

  public async create(): Promise<void> {
    const { ctx } = this;
    const { title } = ctx.request.body;
    ctx.body = await ctx.service.post.create(title);
  }

  public async update(): Promise<void> {
    const { ctx } = this;
    ctx.body = await ctx.service.post.update(ctx.params.id, ctx.request.body);
  }

  // public async destroy(): Promise<void> {}
}
