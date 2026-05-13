class MacroWrappedHandler < Marten::Handler
  route_definition do
    def get
      value = MacroService.call
      respond MacroPresenter.render(value)
    end
  end
end
