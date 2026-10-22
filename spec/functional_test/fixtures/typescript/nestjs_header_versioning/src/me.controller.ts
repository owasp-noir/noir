import { Controller, Get } from "@nestjs/common";

import { ALL_VERSIONS } from "./versions";

@Controller({
  path: "/v2/me",
  version: ALL_VERSIONS,
})
export class MeController {
  @Get("/")
  me() {
    return {};
  }
}
