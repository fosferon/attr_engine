defmodule AttrEngine.Test.InMemoryAdapter do
  @moduledoc """
  In-memory relation adapter for tests.

  Uses an Agent to store key-value pairs, proving the adapter contract
  without any external dependencies.
  """
  @behaviour AttrEngine.Relation

  def start_link(initial \\ %{}) do
    Agent.start_link(fn -> initial end, name: __MODULE__)
  end

  def stop do
    try do
      if Process.whereis(__MODULE__), do: Agent.stop(__MODULE__)
    catch
      :exit, _ -> :ok
    end
  end

  def get_all do
    Agent.get(__MODULE__, & &1)
  end

  @impl true
  def resolve(ref, _config) do
    case Agent.get(__MODULE__, &Map.get(&1, ref)) do
      nil -> {:error, :not_found}
      value -> {:ok, value}
    end
  end

  @impl true
  def store(value, config) do
    ref = config["ref_key"] || "ref_#{:erlang.unique_integer([:positive])}"
    Agent.update(__MODULE__, &Map.put(&1, ref, value))
    {:ok, ref}
  end

  @impl true
  def delete(ref, _config) do
    Agent.update(__MODULE__, &Map.delete(&1, ref))
    :ok
  end
end
