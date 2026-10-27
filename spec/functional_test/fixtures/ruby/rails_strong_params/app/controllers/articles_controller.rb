class ArticlesController < ApplicationController
  BASE_FIELDS = %i[title body].freeze

  def update
    return head :unprocessable_entity unless params[:article].is_a?(ActionController::Parameters)

    Article.find(params[:id]).update(article_params)
  end

  private

  def article_params
    allowed = [*BASE_FIELDS, { tags: [] }]
    allowed << :pinned if current_user.admin?
    params.require(:article).permit(allowed)
  end
end
