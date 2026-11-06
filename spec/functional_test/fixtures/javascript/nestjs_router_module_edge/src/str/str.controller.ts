import { Controller, Get } from '@nestjs/common';

@Controller('str')
export class StrController {
  @Get()
  root() { return 'str'; }
}
