require "./actix_web"

module Analyzer::Rust
  # ntex (https://github.com/ntex-rs/ntex) is an actix-web fork that keeps
  # the same routing surface: `#[web::get("/p")]` attribute macros,
  # `web::resource("/p").route(web::get().to(h))`, `.route("/p", ...)`,
  # `web::scope("/prefix")` and `.configure(fn)`. The tree-sitter walk in
  # `ActixWeb` already matches those shapes by their last path segment, so
  # this adapter only swaps the crate gate and the extractor spellings.
  class Ntex < ActixWeb
    analyzer_for "rust_ntex"

    protected def crate_dependencies : Array(String)
      ["ntex"]
    end

    # ntex 3 adds `.to_with_state(handler)` next to `.to(handler)` for
    # handlers that take `&State` as their first argument.
    protected def handler_binder?(name : String) : Bool
      name == "to" || name == "to_with_state"
    end

    # ntex keeps its extractors in `web::types` (`web::types::Json<T>`,
    # `types::Query<T>`), and its examples import them bare (`Json<T>`) as
    # often as not. The crate gate already limits this to ntex crates, so a
    # bare `Json<` is ntex's extractor here.
    EXTRACTOR_RES = %w[Query Json Form].to_h do |kind|
      {kind, /(?<![\w:])(?:(?:ntex::)?web::)?(?:types::)?#{kind}\s*</}
    end

    protected def extractor_param?(text : String, kind : String) : Bool
      text.matches?(EXTRACTOR_RES[kind])
    end
  end
end
