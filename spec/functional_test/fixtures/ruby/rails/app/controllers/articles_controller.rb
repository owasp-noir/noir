class ArticlesController < ApplicationController
  # permit wrapped across lines
  def create
    @article = Article.create(article_params)
    # a `permit(` inside a string literal must not open a permit list
    logger.info "calling permit( now"
    Thing.create(params.require(:thing).permit(:alpha, :beta))
    Other.create(params.require(:other)
                       .permit(:gamma))
    # a nested read names its leaf; a scalar `require` names its key
    @article.flagged = params[:article][:flag] == "1"
    @source = params.require(:ref)
    # an unclosed `permit(` (heredoc body) must not swallow the next action
    note = <<~TXT
      see permit( docs
    TXT
  end

  # nested `key: []` / `key: {}` entries
  def update
    @article.update(params.require(:article).permit(:one, tags: [], meta: { a: 1 }, "cat" => []))
  end

  private

  def article_params
    params.require(:article).permit(
      :title,
      :body, # trailing comment
      current_user.admin? ? :pinned : nil
    )
  end
end
