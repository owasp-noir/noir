import { Controller, Get, Post, Body } from '@nestjs/common';

abstract class HealthBase {
  @Get('ping')
  ping() { return 'pong'; }
}

@Controller('orders')
export class OrdersController extends HealthBase {
  @Post()
  create(@Body('sku') sku: string) { return sku; }
}

@Controller('invoices')
export class InvoicesController extends HealthBase {}

// Not a controller: inherits routes nobody serves.
export class PlainService extends HealthBase {}
