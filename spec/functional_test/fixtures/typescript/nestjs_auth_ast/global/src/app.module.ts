import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { JwtAuthGuard } from './jwt-auth.guard';
@Module({ providers: [{ provide: APP_GUARD, useClass: JwtAuthGuard }] })
export class AppModule {}
