import { Controller, Get } from '@nestjs/common';

@Controller('me')
export class PublicController {
  @Get()
  getMe(): string { return 'me'; }
}
