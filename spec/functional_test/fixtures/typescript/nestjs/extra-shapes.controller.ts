import { Controller, Get, Post, Patch, All, Body, Param, Query, Headers, ParseIntPipe } from '@nestjs/common';

const API_PREFIX = 'api';

enum RouteName {
  Users = 'users',
}

const AdminRoutes = {
  root: 'admin',
  detail: ':id',
} as const;

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

// Constants, enum members, object members, string concatenation, and
// path arrays show up frequently once NestJS apps split route names
// into shared modules.
@Controller(API_PREFIX + '/' + RouteName.Users)
export abstract class ConstantRoutesController {
  @Get(AdminRoutes.detail)
  detail(
    @Param('id', ParseIntPipe) id: number,
    @Query('includeInactive', ParseIntPipe) includeInactive: boolean,
    @Headers('x-tenant-id') tenantId: string,
  ) {
    return { id, includeInactive, tenantId };
  }

  @Post(['bulk', 'import'])
  upload(@Body('name', ParseIntPipe) name: string) {
    return { name };
  }

  @Patch('profile')
  updateProfile(@Body(new ParseIntPipe()) dto: any) {
    return dto;
  }
}

@Controller(['public', 'internal'])
class MultiPrefixController {
  @Get('health')
  health() {
    return { ok: true };
  }
}

@Controller(AdminRoutes.root)
export default class DefaultExportController {
  @All('status')
  status() {
    return {};
  }
}
