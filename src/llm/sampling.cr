module LLM::Sampling
  # `--ai-temperature` / `--ai-seed`, set once per scan. Nil keeps each
  # request path's own default (0.3, or 0 for agent tool calls) and sends
  # no seed.
  class_property temperature : Float64? = nil
  class_property seed : Int64? = nil
end
