import { router } from "../../trpc";
import { get } from "./procedures/get";

export const meRouter = router({
  get,
});
