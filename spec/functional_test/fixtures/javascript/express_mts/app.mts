import express from "express";

const app = express();

app.get("/hello", (req, res) => {
  res.send(req.query.name);
});

app.listen(3000);
