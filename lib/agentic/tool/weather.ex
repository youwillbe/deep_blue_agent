defmodule Agentic.Tool.Weather do
  use Jido.Action,
    name: "get_weather",
    description: "Get current weather for a given city",
    schema: [
      city: [type: :string, required: true, doc: "The city name to get weather for"]
    ]

  @impl true
  def run(params, _ctx) do
    # Mock data
    {:ok,
     %{
       city: params.city,
       temperature: 22,
       condition: "sunny",
       humidity: 55
     }}
  end
end
