import { Controller, Get } from "@nestjs/common";

// The last key keeps its trailing comma.
@Controller({
  path: "/v2/verified-resources",
})
export class VerifiedResourcesController {
  @Get("/emails")
  emails() {
    return [];
  }
}
