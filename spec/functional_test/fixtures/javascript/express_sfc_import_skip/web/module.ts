// A Vue module-definition file: it wires up Single-File Components and
// also fires a wrapped API client. Importing a `.vue` component marks it
// as frontend, so the `api.patch(...)` outbound call must NOT be emitted
// as an Express endpoint.
import Overview from './Overview.vue';
import api from './api';

export default {
  routes: [Overview],
  async save(collection) {
    await api.patch(`/collections/${collection}`, { meta: {} });
  },
};
