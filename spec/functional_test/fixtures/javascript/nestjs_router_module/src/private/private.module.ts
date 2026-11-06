import { Module } from '@nestjs/common';
import { PrivateController } from './private.controller';

@Module({
  controllers: [PrivateController],
})
export class PrivateModule {}
