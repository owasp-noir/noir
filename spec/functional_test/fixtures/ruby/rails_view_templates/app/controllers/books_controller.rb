# Rails guide "Layouts and Rendering", 2.1 Rendering by Default: no `index`
# method, app/views/books/index.html.erb is rendered.
class BooksController < ApplicationController
  def show
    @book = Book.find(params[:id])
  end
end
