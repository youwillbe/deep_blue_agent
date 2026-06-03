defmodule Agentic.Tool.Adapter do
  @moduledoc """
  Converts Jido Actions into ReqLLM.Tool structs for LLM consumption.
  """

  @doc """
  Converts a list of action modules into ReqLLM.Tool structs.
  """
  def from_actions(modules) do
    Enum.map(modules, &from_action/1)
  end

  def from_action(module) do
    json_schema = Jido.Action.Schema.to_json_schema(module.schema())

    ReqLLM.Tool.new!(
      name: module.name(),
      description: module.description(),
      parameter_schema: json_schema,
      callback: fn _args -> {:ok, %{}} end
    )
  end
end
