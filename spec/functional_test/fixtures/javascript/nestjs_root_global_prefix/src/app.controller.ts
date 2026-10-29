import { Controller, Get } from '@nestjs/common';
@Controller()
export class AppController {
  @Get()
  root(): string { return 'ok'; }

  @Get('health')
  health(): string { return 'ok'; }
}
