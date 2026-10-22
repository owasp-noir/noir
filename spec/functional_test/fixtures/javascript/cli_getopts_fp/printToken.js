// Old shell wrapper used getopts for flag parsing; now just env-driven.
// Regression guard: the bare word "getopts" in this comment must not be
// enough to treat this file as CLI-parsing evidence.
module.exports = function printToken() {
  console.log(process.env.API_TOKEN);
};
