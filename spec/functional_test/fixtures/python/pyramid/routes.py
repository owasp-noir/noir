def includeme(config):
    config.add_route("external_report", "/external/reports/{report_id}")
