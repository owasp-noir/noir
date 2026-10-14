import { useSignal } from "@preact/signals";
import { define } from "../utils.ts";

export default define.page(function Home(ctx) {
  const count = useSignal(3);
  return <div>Fresh</div>;
});
