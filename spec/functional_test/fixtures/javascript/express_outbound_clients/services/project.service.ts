import { APIService } from "@/services/api.service";

// An API client class: `this.post` is an outbound axios call.
export class ProjectService extends APIService {
  async createProject(workspaceSlug: string, data: object) {
    return this.post(`/api/workspaces/${workspaceSlug}/projects/`, data);
  }

  async updateProject(workspaceSlug: string, projectId: string, data: object) {
    return this.patch(`/api/workspaces/${workspaceSlug}/projects/${projectId}/`, data);
  }
}
