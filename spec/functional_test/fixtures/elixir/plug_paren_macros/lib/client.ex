defmodule MyApp.Client do
  def users do
    get("/api/users")
  end

  defp get(path), do: Req.get!(path)
end
