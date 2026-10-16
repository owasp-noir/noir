import APIService from './api-service';

// Outbound calls of an API client class: the value is used, or the argument
// is data, never a handler.
export default class ProjectService extends APIService {
  load(id) {
    return this.get(`/client-projects/${id}`, { headers: {} });
  }
  create(body) {
    return this.post('/client-projects', body);
  }
  upload(file) {
    return this.post('/client-files', file, { onProgress: () => {} });
  }
  rename(id, name) {
    return this.patch('/client-rename/' + id, this.payload(name));
  }
  sync() {
    return this.put('/client-sync', this.defaults);
  }
}
