# This class handles error responses and reporting.
#
# https://luckyframework.org/guides/http-and-routing/error-handling
class Errors::Show < Lucky::ErrorAction
  DEFAULT_MESSAGE = "Something went wrong."
  default_format :json
  dont_report [Lucky::RouteNotFoundError, Avram::RecordNotFoundError]

  def render(error : Lucky::RouteNotFoundError | Avram::RecordNotFoundError)
    error_json "Not found", status: 404
  end

  # When an InvalidOperationError is raised, show a helpful error with the
  # param that is invalid, and what was wrong with it.
  def render(error : Avram::InvalidOperationError)
    error_json \
      message: error.renderable_message,
      details: error.renderable_details,
      param: error.invalid_attribute_name,
      status: 400
  end

  # Always keep this below other 'render' methods or it may override your
  # custom 'render' methods.
  def render(error : Lucky::RenderableError)
    error_json error.renderable_message, status: error.renderable_status
  end

  # If none of the 'render' methods return a response for the raised Exception,
  # Lucky will use this method.
  def default_render(error : Exception) : Lucky::Response
    error_json DEFAULT_MESSAGE, status: 500
  end

  private def error_json(message : String, status : Int, details = nil, param = nil)
    json ErrorSerializer.new(message: message, details: details, param: param), status: status
  end

  private def report(error : Exception) : Nil
    # Send to Rollbar, send an email, etc.
  end
end
