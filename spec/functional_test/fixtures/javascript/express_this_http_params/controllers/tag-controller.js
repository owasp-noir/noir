import Controller from '../controller';

// Extends a local base class and imports no server library itself.
export default class TagController extends Controller {
  constructor(config, { tagService }) {
    super(config);
    this.tagService = tagService;
    this.get('/tags', this.getTags);
    this.post('/tags', this.createTag, ADMIN);
    this.put('/tags/:name', req => this.update(req));
    this.delete('/tags/:name', this.removeTag);
  }
}
