import { Controller, Get } from '@nestjs/common';

@Controller('z')
export class ZooController {
  @Get()
  root() { return 'z'; }
}
