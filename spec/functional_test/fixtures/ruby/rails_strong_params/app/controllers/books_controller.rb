class BooksController < ApplicationController
  class Serializer
    ALLOWED = %i[isbn_wrong]

    def permitted
      [:wrong_a]
    end
  end

  def create
    Book.create(params.require(:book).permit(permitted))
  end

  def update
    return Book.find(params[:id]).update(title: params[:book]) if params[:book].is_a?(String)

    Book.find(params[:id]).update(params.require(:book).permit(ALLOWED))
  end

  private

  def permitted
    if current_user.admin?
      [:title, :author]
    else
      [:title]
    end
  end
end
