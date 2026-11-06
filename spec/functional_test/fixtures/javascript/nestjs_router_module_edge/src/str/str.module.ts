import { Module } from '@nestjs/common';
import { StrController } from './str.controller';

@Module({ controllers: [StrController] })
export class StrModule {}
