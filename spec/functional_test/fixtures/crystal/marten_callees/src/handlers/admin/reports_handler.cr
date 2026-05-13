module Admin
  class ReportsHandler < Marten::Handler
    def get
      report = ReportService.latest
      respond ReportSerializer.render(report)
    end
  end
end
