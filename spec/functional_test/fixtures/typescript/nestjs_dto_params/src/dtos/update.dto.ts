import { IntersectionType, OmitType, PartialType, PickType as Select } from '@nestjs/mapped-types';
import { CreateItemDto } from './create-item.dto.js';

class Revision {
  constructor(public readonly revision: number, private readonly cacheKey: string) {}
}

export default class UpdateDto extends IntersectionType(
  PartialType(OmitType(Select(CreateItemDto, ['name', 'tags'] as const), ['tags'] as const)),
  Revision,
) {
  reason?: string;
}

class ScopeDto {
  id!: string;
  rest!: string[];
}
export { ScopeDto as Scope };

export interface Attributes { [key: string]: unknown }

export type ConditionalHeaders = { 'if-none-match'?: string };
