import { IsOptional } from 'class-validator';

export class CursorPaginationQueryDto<T, K extends keyof T> {
  @IsOptional()
  after?: string;

  @IsOptional()
  limit?: number;

  orderBy?: K;
}

export class ListItemsQueryDto extends CursorPaginationQueryDto<ItemDto, 'id'> {
  @IsOptional()
  search?: string;
}
