import Fastify from 'fastify';
import literalRoutes from './routes/literal';
import templateRoutes from './routes/template';
import concatRoutes from './routes/concat';
import localRoutes from './routes/local';
import { constRoutes } from './routes/const';
import { API_PREFIX } from './config';

const LOCAL_PREFIX = '/local';
const app = Fastify();

app.register(literalRoutes, { prefix: '/literal' });
app.register(templateRoutes, { prefix: `${API_PREFIX}/template` });
app.register(concatRoutes, { prefix: API_PREFIX + '/concat' });
app.register(localRoutes, { prefix: `${LOCAL_PREFIX}/v1` });
app.register(constRoutes, { prefix: API_PREFIX });

app.listen({ port: 3000 });
