class ArticlesController < ApplicationController
  # permit wrapped across lines
  def create
    @article = Article.create(article_params)
    logger.info "unbalanced permit( in a string"
  end

  # nested `key: []` / `key: {}` entries
  def update
    @article.update(params.require(:article).permit(:one, tags: [], meta: { a: 1 }, "cat" => []))
  end

  private

  def article_params
    params.require(:article).permit(
      :title,
      :body # trailing comment
    )
  end
end
