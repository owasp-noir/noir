import { Controller, Get, Param } from '@nestjs/common';
import { RouteKey } from './enum';

// The controller prefix is an enum member imported from another file.
@Controller(RouteKey.User)
export class UsersController {
  @Get('me')
  me() {
    return {};
  }

  @Get(':id')
  show(@Param('id') id: string) {
    return { id };
  }
}
