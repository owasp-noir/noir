import http from 'k6/http';

export default function () {
  http.post('/webhook/binary-files-benchmark', payload);
}
