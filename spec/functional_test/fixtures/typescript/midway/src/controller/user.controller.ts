import { Controller, Get, Post, Put, Del, All, Inject, Query, Param, Body, Headers } from '@midwayjs/core';
import { Context } from '@midwayjs/koa';
import { AuthMiddleware } from '../middleware/auth.middleware';

@Controller('/api/users', { middleware: [AuthMiddleware], tagName: 'users' })
export class UserController {
  @Inject()
  ctx: Context;

  @Get('/', { summary: 'list users' })
  async list(@Query('page') page: number, @Query('size') size: number) {
    return [];
  }

  @Get('/:id')
  async show(@Param('id') id: string) {
    return { id };
  }

  @Post('/', { middleware: [AuthMiddleware] })
  async create(@Body() body: any, @Headers('x-request-id') requestId: string) {
    return body;
  }

  @Put('/:id')
  async update(@Param('id') id: string, @Body('name') name: string) {
    return { id, name };
  }

  @Del('/:id')
  async remove(@Param('id') id: string) {
    return { id };
  }

  // @Get('/legacy')
  @All('/ping')
  async ping() {
    return 'pong';
  }
}
