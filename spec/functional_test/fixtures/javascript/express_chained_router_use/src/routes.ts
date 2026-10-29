import { Router } from 'express';
import itemsController from './items/items.controller';

const api = Router()
  .use(itemsController);

export default Router().use('/api', api);
