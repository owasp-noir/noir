import { Controller, Get } from '@nestjs/common';

@Controller({ path: 'users', version: '1' })
export class AdminController {
  @Get()
  list() { return []; }
}
