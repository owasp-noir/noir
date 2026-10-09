export const getReports = async ({ year, quarter }, context) => {
  return context.entities.Report.findMany({ where: { year, quarter } });
};

export const reportCsv = (req, res) => {
  res.type("text/csv").send(`id,${req.query.columns}`);
};
