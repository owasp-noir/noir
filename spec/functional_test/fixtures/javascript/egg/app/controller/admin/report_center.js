'use strict';

exports.create = async ctx => {
  const { period } = ctx.request.body;
  ctx.body = await ctx.service.report.build(period);
};
