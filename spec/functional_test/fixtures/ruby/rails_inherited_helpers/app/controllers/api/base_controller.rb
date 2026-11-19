class Api::BaseController < ApplicationController
  DEFAULT_ACCOUNTS_LIMIT = 40

  protected

  def limit_param(default_limit)
    return default_limit unless params[:limit]

    [params[:limit].to_i.abs, default_limit * 2].min
  end

  # Defined by the parent but called by no action: its read stays put.
  def cursor_param
    params[:cursor]
  end
end
