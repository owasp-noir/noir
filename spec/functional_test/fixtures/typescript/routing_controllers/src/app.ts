import 'reflect-metadata';
import { createExpressServer } from 'routing-controllers';
import { HealthController } from './controllers/HealthController';
import { UserController } from './controllers/UserController';

const app = createExpressServer({
  routePrefix: '/api',
  controllers: [UserController, HealthController],
});

app.listen(3000);
