import { component$ } from "@builder.io/qwik";
import { routeLoader$ } from "@builder.io/qwik-city";

export const useUser = routeLoader$(async ({ params }) => ({ id: params.id }));

export default component$(() => <div>{useUser().value.id}</div>);
