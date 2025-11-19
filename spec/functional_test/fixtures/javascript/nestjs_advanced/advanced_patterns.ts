import { Controller, Get, Post, Put, Delete, Patch, Body, Param, Query, Headers, Req } from '@nestjs/common';

// Case-insensitive/mixed-case decorator patterns
@Controller('mixed')
export class MixedCaseController {
  @Get('get-route')
  mixedGet(@Query('mixedParam') mixedParam: string) {
    return { method: 'GET' };
  }

  @Post('post-route')
  mixedPost(@Body() data: any) {
    return { method: 'POST' };
  }

  @Put('put-route')
  mixedPut(@Body() value: any) {
    return { method: 'PUT' };
  }

  @Delete('delete-route')
  mixedDelete(@Param('id') id: string) {
    return { method: 'DELETE' };
  }

  @Patch('patch-route')
  mixedPatch(@Body() field: any) {
    return { method: 'PATCH' };
  }
}

// Multi-line decorator patterns (common in formatted code)
@Controller('multiline')
export class MultilineController {
  @Get(
    'simple'
  )
  multilineSimple(
    @Query('ml_param') ml_param: string
  ) {
    return { multiline: true };
  }

  @Post(
    'with-decorators'
  )
  multilineWithDecorators(
    @Body('username') username: string,
    @Body('email') email: string,
    @Headers('authorization') authToken: string
  ) {
    return { authenticated: true };
  }
}

// Async/await patterns (standard in NestJS)
@Controller('async')
export class AsyncController {
  @Get('get')
  async asyncGet(@Query('asyncParam') asyncParam: string) {
    const data = await this.fetchData();
    return { data };
  }

  @Post('post')
  async asyncPost(
    @Body('title') title: string,
    @Body('content') content: string,
    @Headers('user-id') userId: string
  ) {
    await this.saveData(title, content);
    return { saved: true };
  }

  private async fetchData() { return {}; }
  private async saveData(title: string, content: string) { }
}

// Path parameters with multiple segments
@Controller('users')
export class UsersPostsController {
  @Get(':userId/posts/:postId')
  getUserPost(
    @Param('userId') userId: string,
    @Param('postId') postId: string,
    @Query('includeComments') includeComments: string
  ) {
    return { userId, postId };
  }
}

// Different parameter extraction patterns
@Controller('extract')
export class ExtractVariationsController {
  @Post('variations')
  extractVariations(
    // Destructuring from body
    @Body('field1') field1: string,
    @Body('field2') field2: string,
    @Body('field3') field3: string,
    
    // Direct body access
    @Body() body: any,
    
    // Query params - different styles
    @Query('query1') query1: string,
    @Query() query: any,
    
    // Headers - different styles
    @Headers('x-custom-header') header1: string,
    @Headers() headers: any,
    
    // Full request object
    @Req() request: any
  ) {
    const directField = body.directField;
    const query2 = query['query2'];
    const header2 = headers['x-another-header'];
    const cookie1 = request.cookies?.sessionId;
    
    return { success: true };
  }
}

// Nested controllers with prefix (common NestJS pattern)
@Controller('api/v2')
export class ApiV2Controller {
  @Get('status')
  getStatus(
    @Query('format') format: string,
    @Headers('x-status-key') statusKey: string
  ) {
    return { status: 'active' };
  }

  @Put('config')
  updateConfig(
    @Body('theme') theme: string,
    @Body('notifications') notifications: any,
    @Req() request: any
  ) {
    const configToken = request.cookies?.configToken;
    return { updated: true };
  }

  // Multi-line in nested controller
  @Post(
    'data'
  )
  processData(
    @Body('values') values: any,
    @Headers('data-key') dataKey: string
  ) {
    return { processed: true };
  }
}

// Admin controller with complex routes
@Controller('admin')
export class AdminController {
  @Get('dashboard')
  async getDashboard(
    @Query('view') view: string,
    @Headers('admin-token') adminToken: string
  ) {
    return { dashboard: {} };
  }

  @Post('users/create')
  async createUser(
    @Body('username') username: string,
    @Body('role') role: string,
    @Body('permissions') permissions: any,
    @Req() request: any
  ) {
    const masterKey = request.cookies?.masterKey;
    return { created: true };
  }

  // Multi-line in admin controller
  @Get(
    'system/logs'
  )
  async getSystemLogs(
    @Query('date') date: string,
    @Query('level') level: string
  ) {
    return { logs: [] };
  }
}

// Route with both params and query
@Controller('items')
export class ItemsController {
  @Get(':category/:id')
  getItem(
    @Param('category') category: string,
    @Param('id') id: string,
    @Query('sort') sort: string,
    @Query('filter') filter: string
  ) {
    return { category, id };
  }
}

// All HTTP methods in one controller
@Controller('catchall')
export class CatchAllController {
  @Get()
  handleGet(@Query('anyParam') anyParam: string) {
    return { method: 'GET' };
  }

  @Post()
  handlePost(@Body() body: any) {
    return { method: 'POST' };
  }

  @Put()
  handlePut(@Body() body: any) {
    return { method: 'PUT' };
  }

  @Delete()
  handleDelete() {
    return { method: 'DELETE' };
  }

  @Patch()
  handlePatch(@Body() body: any) {
    return { method: 'PATCH' };
  }
}

// Versioned controllers (NestJS versioning feature)
@Controller({ path: 'versioned', version: '1' })
export class VersionedV1Controller {
  @Get('data')
  getDataV1(@Query('v1Param') v1Param: string) {
    return { version: 1 };
  }
}

@Controller({ path: 'versioned', version: '2' })
export class VersionedV2Controller {
  @Get('data')
  getDataV2(@Query('v2Param') v2Param: string) {
    return { version: 2 };
  }
}

// DTO-based body parameters (common NestJS pattern)
class CreateUserDto {
  username: string;
  email: string;
  password: string;
}

@Controller('dto-users')
export class DtoUsersController {
  @Post()
  createUser(@Body() createUserDto: CreateUserDto) {
    return { created: true };
  }
}

// Multiple decorators on single route
@Controller('decorated')
export class DecoratedController {
  @Get('route')
  decoratedRoute(
    @Query('param1') param1: string,
    @Query('param2') param2: string,
    @Headers('x-header-1') header1: string,
    @Headers('x-header-2') header2: string,
    @Body('field1') field1?: string,
    @Body('field2') field2?: string
  ) {
    return { decorated: true };
  }
}
