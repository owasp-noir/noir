// Generated-style Apollo REST data source. The `this.get(...)` /
// `this.post(...)` calls are OUTBOUND requests to an upstream service,
// not route registrations — but their verb-DSL shape matches the
// parser's route hint. The `@apollo/datasource-rest` import is the
// marker that tells noir to treat these as a client, not a server
// (issue #1903).
import { RESTDataSource } from '@apollo/datasource-rest';

export class UsersAPI extends RESTDataSource {
  override baseURL = 'https://users.internal/';

  getUser(id: string) {
    return this.get(`/ds-leak/users/${id}`);
  }

  createUser(body: object) {
    return this.post('/ds-leak/users', { body });
  }

  deleteUser(id: string) {
    return this.delete(`/ds-leak/users/${id}`);
  }
}
