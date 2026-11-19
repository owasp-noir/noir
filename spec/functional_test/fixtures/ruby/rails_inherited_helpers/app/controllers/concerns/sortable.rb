module Sortable
  extend ActiveSupport::Concern

  def sort_options
    { by: params[:sort_by], dir: params.fetch(:sort_dir, "asc") }
  end
end
