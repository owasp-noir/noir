import { Controller, Get, Param } from '@nestjs/common';
import { BaseController } from '../common/base.controller';

export class CreateUserDto { email: string; name: string; }

@Controller('users')
export class UsersController extends BaseController<CreateUserDto> {
  @Get('me')
  me() { return {}; }

  // Redefined: the base class's `GET :id` is no longer served.
  @Get('by-uid/:uid')
  findOne(@Param('uid') uid: string) { return {}; }
}
