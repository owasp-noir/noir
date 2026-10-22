import { Controller, Get } from '@nestjs/common';

@Controller('alpha')
export class AlphaController {
  @Get('ping')
  ping() {
    return 'ok';
  }
}
