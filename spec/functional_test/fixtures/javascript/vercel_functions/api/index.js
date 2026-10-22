module.exports = (req, res) => {
  res.send(`session ${req.cookies.session}`);
};
