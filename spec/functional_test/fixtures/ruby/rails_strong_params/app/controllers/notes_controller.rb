class NotesController < ApplicationController
  def create
    note = params[:note]
    Note.create(text: note[:text], color: note[:color])
  end
end
