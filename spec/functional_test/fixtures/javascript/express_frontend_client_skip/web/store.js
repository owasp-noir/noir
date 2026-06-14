// SPA store: a wrapped axios client (`api`) makes OUTBOUND calls. These
// are NOT route registrations — the pinia import marks this as browser
// code, so its `api.get(...)` / `api.post(...)` calls must be skipped
// rather than emitted as phantom Express endpoints.
import { defineStore } from 'pinia';
import api from './api';

export const useUsers = defineStore('users', {
  actions: {
    load(id) {
      return api.get(`/users/${id}`);
    },
    create(payload) {
      return api.post('/users', payload);
    },
    remove(id) {
      return api.delete(`/users/${id}`);
    },
  },
});
