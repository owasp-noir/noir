import { defaultResponder } from "../../lib/responder";

async function handler(req, res) {
  const booking = await createBooking(req.body);
  return booking;
}

export default defaultResponder(handler, "/api/book");
