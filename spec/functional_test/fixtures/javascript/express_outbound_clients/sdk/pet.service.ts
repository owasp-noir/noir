import { inject, injectable } from "inversify";
import IHttpClient from "../IHttpClient";

@injectable()
export class PetService {
  @inject("IApiHttpClient") private httpClient: IHttpClient;

  public addPet(body: object, headers: object) {
    return this.httpClient.post(`${this.cfg.basePath}/pet`, body as any, headers);
  }
}
