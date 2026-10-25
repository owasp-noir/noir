import { Controller, Get } from '@nestjs/common';

@Controller('health')
export class HealthController {
  @Get()
  check() { return 'ok'; }
}

@Controller('items')
export class ItemsController {
  @Get()
  list() { return []; }
}
