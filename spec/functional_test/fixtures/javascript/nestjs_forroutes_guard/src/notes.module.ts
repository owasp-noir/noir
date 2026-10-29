import { Module, NestModule, MiddlewareConsumer, RequestMethod } from '@nestjs/common';
import { NotesController } from './notes.controller';
import { AuthMiddleware } from './auth.middleware';

@Module({ controllers: [NotesController] })
export class NotesModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer
      .apply(AuthMiddleware)
      .exclude({ path: 'notes', method: RequestMethod.GET })
      .forRoutes(NotesController);
  }
}
