import { Module, NestModule, MiddlewareConsumer, RequestMethod } from '@nestjs/common';
import { ItemsController } from './items.controller';
import { AuthMiddleware } from './auth.middleware';

@Module({ controllers: [ItemsController] })
export class ItemsModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer
      .apply(AuthMiddleware)
      .forRoutes({ path: 'items', method: RequestMethod.POST });
  }
}
