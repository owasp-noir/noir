import { Configuration } from "@tsed/di";
import "@tsed/platform-express";
import * as rest from "./controllers/index";

@Configuration({
  acceptMimes: ["application/json"],
  mount: {
    "/rest": [...Object.values(rest)],
  },
})
export class Server {}
