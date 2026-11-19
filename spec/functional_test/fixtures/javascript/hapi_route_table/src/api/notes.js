const { addNoteHandler, getAllNotesHandler, deleteNoteByIdHandler } = require('../handlers/notes');

const routes = [
  { method: 'POST', path: '/notes', handler: addNoteHandler },
  { method: 'GET', path: '/notes', handler: getAllNotesHandler },
  { method: 'DELETE', path: '/notes/{id}', handler: deleteNoteByIdHandler },
];

module.exports = routes;
