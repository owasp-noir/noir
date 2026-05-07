package demo

// Abstract base controller used as a template for subclasses; its
// actions are not directly addressable.
abstract class BaseController {
    def shared() {
        render 'shared'
    }
}
