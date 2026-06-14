import { type LoaderFunctionArgs, type ActionFunctionArgs } from "@remix-run/node";

// The trailing `_` on `$contactId_` is Remix's "opt out of parent layout"
// marker — it does not affect the URL or the param name. The route is
// `/contacts/{contactId}/edit`.
export const loader = async ({ params }: LoaderFunctionArgs) => {
  return { id: params.contactId };
};

export const action = async ({ params }: ActionFunctionArgs) => {
  return { id: params.contactId };
};
