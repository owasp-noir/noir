// Lambda-compatible (v1) function, served at /.netlify/functions/legacy.
exports.handler = async (event, context) => {
  if (event.httpMethod !== "POST") {
    return { statusCode: 405 };
  }
  const { page } = event.queryStringParameters;
  const { title } = JSON.parse(event.body);
  return { statusCode: 200, body: JSON.stringify({ page, title }) };
};
