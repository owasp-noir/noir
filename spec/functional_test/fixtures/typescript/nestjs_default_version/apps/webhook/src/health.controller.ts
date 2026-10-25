import { Controller, Get } from '@nestjs/common';

@Controller('v1/health-check')
export class HealthController {
  @Get()
  check() {
    return 'ok';
  }
}
