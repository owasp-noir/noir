import { Controller, Get, Post, Body, Param } from '@nestjs/common';

// Empty @Controller() — routes use the method path as-is.
@Controller()
export class RootController {
  @Get('health')
  health() {
    return { ok: true };
  }
}

// Object syntax on a single line.
@Controller({ path: 'tasks', version: '1' })
export class TasksController {
  @Get()
  list() {
    return [];
  }

  @Post()
  create(@Body() dto: any) {
    return {};
  }
}

// Object syntax spanning multiple lines — common in larger
// NestJS apps where the decorator carries auth/version metadata.
@Controller({
  path: 'webhooks',
  version: '1',
})
export class WebhooksController {
  @Post(':provider')
  receive(@Param('provider') provider: string, @Body() body: any) {
    return { provider };
  }
}
