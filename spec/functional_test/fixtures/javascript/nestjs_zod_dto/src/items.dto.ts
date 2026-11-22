import { createZodDto } from 'nestjs-zod';
import { optionalFields } from './validation';
import { z } from 'zod';
const ItemCreateSchema = z.object({ name: z.string(), price: z.number() });
const ItemSearchSchema = z.object({ q: z.string().optional(), page: z.number().optional() });
export class ItemCreateDto extends createZodDto(ItemCreateSchema) {}
export class ItemSearchDto extends createZodDto(ItemSearchSchema) {}
export class ItemClassDto { name: string; price: number; }

enum WireKey { Label = 'display-label' }
const Details = z
  .object({ [WireKey.Label]: z.string(), nested: z.object({ internal: z.string() }) })
  .describe('Item details');
const Alias = Details;
const Published = Alias.extend({ timestamp: z.number() });
const validated = <T extends z.ZodObject>(schema: T) => {
  const hasLabel = (item: Record<string, unknown>) => WireKey.Label in item;
  return schema.refine(hasLabel);
};
const Selected = validated(Published.pick({ [WireKey.Label]: true, timestamp: true }))
  .transform((item) => ({ outputOnly: item.timestamp }))
  .pipe(z.object({ outputOnly: z.number() })).meta({ id: 'Published' });
export class PublishedDto extends createZodDto(Selected) {}
const Extra = optionalFields({ region: z.string() }).default({});
const Filter = Published.omit({ timestamp: true });
export class FilterDto extends createZodDto(Filter) {}
const Dynamic = customFactory(Details);
export class DynamicDto extends createZodDto(Dynamic) {}
export class ExtraDto extends createZodDto(Extra) {}
