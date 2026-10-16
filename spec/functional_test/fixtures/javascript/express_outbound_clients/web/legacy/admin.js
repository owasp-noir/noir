// Browser code: jQuery and a local AJAX helper calling the backend.
function save(data) {
  $.post('/admin/save', data, function (res) {
    console.log(res);
  });
}

function upload(body) {
  return AJAX.put('/apps/upload', body);
}
