import { Controller, Get, Post } from '@nestjs/common';

@Controller('me')
export class PrivateController {
  @Get()
  getMe(): string { return 'me'; }

  @Post('profile')
  update(): string { return 'ok'; }
}
