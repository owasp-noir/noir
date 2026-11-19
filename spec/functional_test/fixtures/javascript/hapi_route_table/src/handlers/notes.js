const addNoteHandler = (request, h) => h.response(request.payload).code(201);
const getAllNotesHandler = (request, h) => [];
const deleteNoteByIdHandler = (request, h) => ({ id: request.params.id });
module.exports = { addNoteHandler, getAllNotesHandler, deleteNoteByIdHandler };
