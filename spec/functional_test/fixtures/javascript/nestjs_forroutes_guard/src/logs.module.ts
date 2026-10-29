import { Module, NestModule, MiddlewareConsumer, RequestMethod } from '@nestjs/common';
import { LogsController } from './logs.controller';
import { LogMiddleware } from './auth.middleware';

@Module({ controllers: [LogsController] })
export class LogsModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer
      .apply(LogMiddleware)
      .forRoutes({ path: 'logs', method: RequestMethod.POST });
  }
}
