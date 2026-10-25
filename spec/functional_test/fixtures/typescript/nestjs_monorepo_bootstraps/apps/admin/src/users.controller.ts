import { Controller, Get } from '@nestjs/common';

// The admin app has no bootstrap in this checkout; as its own Nx
// application it takes nothing from apps/api.
@Controller('users')
export class UsersController {
  @Get()
  list() { return []; }
}
