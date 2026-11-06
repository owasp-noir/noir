import { Module } from '@nestjs/common';
import { SharedController } from './shared.controller';

@Module({ controllers: [SharedController] })
export class SharedModule {}
