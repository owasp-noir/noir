import { Controller, Get } from '@nestjs/common';
import { Public } from './public.decorator';

@Controller('items')
export class ItemsController {
  // @Public()
  @Get('was-public')
  wasPublic() { return 1; }

  @Get('public')
  @Public()
  open() { return 1; }

  @Get(
    'private',
  )
  /* @Public() */
  closed() { return 1; }
}
