import { App } from "wasp-config";

const app = new App("legacyTsApp", {
  title: "Legacy TS config",
  wasp: { version: "^0.16.0" },
});

app.auth({
  userEntity: "User",
  methods: {
    usernameAndPassword: {},
  },
  onAuthFailedRedirectTo: "/login",
});

const dashboardPage = app.page("DashboardPage", {
  component: { importDefault: "Dashboard", from: "@src/Dashboard" },
  authRequired: true,
});
app.route("DashboardRoute", { path: "/dashboard", to: dashboardPage });

app.query("getReports", {
  fn: { import: "getReports", from: "@src/reports" },
  entities: ["Report"],
});

app.api("reportCsv", {
  fn: { import: "reportCsv", from: "@src/reports" },
  httpRoute: { method: "GET", route: "/reports/:reportId/csv" },
  auth: false,
});
