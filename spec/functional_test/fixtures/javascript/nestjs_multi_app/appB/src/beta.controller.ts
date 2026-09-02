import { Controller, Get } from '@nestjs/common';

@Controller('beta')
export class BetaController {
  @Get('ping')
  ping() {
    return 'ok';
  }
}
