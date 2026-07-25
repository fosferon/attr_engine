defmodule AttrEngine.Relation do
  @moduledoc """
  Relation resolution runtime for reference attributes.

  An attribute with `data_config.type = "relation"` stores a **ref** (an
  opaque identifier) in the ASD, while the actual value lives in an
  external target store. This module orchestrates the read and write paths
  through pluggable source adapters.

  ## relation_config shape

  The `relation_config` map on an attribute's data_config drives resolution:

      %{
        "source" => "vault",       # adapter name (looked up in registry)
        "ref_only" => true,        # if true, value never materializes into ASD
        ...                        # adapter-specific keys passed through
      }

  Any additional keys in `relation_config` are passed to the adapter as
  context, allowing adapter-specific configuration (table names, column
  mappings, scopes, etc.) without the engine knowing about them.

  ## Registering source adapters

  Adapters implement the `AttrEngine.Relation` behaviour and are registered
  via application config:

      config :attr_engine, relation_sources: %{
        "vault" => MyApp.Adapters.Vault,
        "users" => MyApp.Adapters.Users
      }

  ## Behaviour

  Adapters must implement three callbacks:

      defmodule MyApp.Adapters.Vault do
        @behaviour AttrEngine.Relation

        @impl true
        def resolve(ref, config) do
          # ref: the stored reference (e.g. secret name)
          # config: the full relation_config map
          case Vault.get(ref) do
            {:ok, value} -> {:ok, value}
            :error -> {:error, :not_found}
          end
        end

        @impl true
        def store(value, config) do
          # Persist value to the target store, return a ref
          name = config["ref_key"] || generate_name()
          :ok = Vault.put(name, value)
          {:ok, name}
        end

        @impl true
        def delete(ref, config) do
          Vault.delete(ref)
          :ok
        end
      end

  ## Composition with transforms

  For sensitive relations (secrets, credentials), pair `ref_only: true`
  with `data_config["transform"] = "redact_secret"`. The transform masks
  the ref in rendered/exposed output while the resolution system handles
  the actual value routing.
  """

  @doc "Resolve a ref to its target value."
  @callback resolve(ref :: any(), config :: map()) :: {:ok, any()} | {:error, any()}

  @doc "Store a value in the target, returning the ref to persist in the ASD."
  @callback store(value :: any(), config :: map()) :: {:ok, ref :: any()} | {:error, any()}

  @doc "Delete the target value for the given ref."
  @callback delete(ref :: any(), config :: map()) :: :ok | {:error, any()}

  @doc """
  Resolves all relation attributes in a data map.

  For each attribute in `attrs_meta` where `type == :relation` (or
  `data_config["type"] == "relation"`), looks up the source adapter and
  resolves the stored ref to its target value.

  Options:
  - `:skip_ref_only` — when true (default), skips resolution for
    `ref_only: true` relations (the ref stays as-is, to be masked by
    the transform layer). Set to false to force resolution of all.

  Returns `{:ok, resolved_data}` or `{:error, errors}` where errors is
  a list of `{handle, reason}` tuples.
  """
  @spec resolve_relations([map()], map(), keyword()) :: {:ok, map()} | {:error, [{String.t(), any()}]}
  def resolve_relations(attrs_meta, data, opts \\ []) do
    skip_ref_only = Keyword.get(opts, :skip_ref_only, true)

    {resolved, errors} =
      attrs_meta
      |> relation_attributes()
      |> Enum.reduce({data, []}, fn %{handle: handle, data_config: dc}, {acc, errs} ->
        rc = dc["relation_config"] || %{}

        if skip_ref_only && rc["ref_only"] == true do
          {acc, errs}
        else
          ref = Map.get(data, handle)
          resolve_one(handle, ref, rc, acc, errs)
        end
      end)

    case errors do
      [] -> {:ok, resolved}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  @doc """
  Processes incoming data for write, routing values to their target stores.

  For each relation attribute marked `ref_only: true`, extracts the raw
  value from `incoming_data`, passes it to the adapter's `store/2`, and
  replaces it with the returned ref in the output data.

  Non-relation attributes and relations without `ref_only` are passed
  through unchanged.

  Returns `{:ok, processed_data}` or `{:error, errors}`.
  """
  @spec process_writes([map()], map()) :: {:ok, map()} | {:error, [{String.t(), any()}]}
  def process_writes(attrs_meta, incoming_data) do
    {processed, errors} =
      attrs_meta
      |> relation_attributes()
      |> Enum.filter(fn %{data_config: dc} ->
        rc = dc["relation_config"] || %{}
        rc["ref_only"] == true
      end)
      |> Enum.reduce({incoming_data, []}, fn %{handle: handle, data_config: dc}, {acc, errs} ->
        rc = dc["relation_config"] || %{}
        value = Map.get(incoming_data, handle)

        if is_nil(value) do
          {acc, errs}
        else
          store_one(handle, value, rc, acc, errs)
        end
      end)

    case errors do
      [] -> {:ok, processed}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  @doc """
  Deletes target values for all relation attributes in the given data.

  Useful when deleting an ASD, to clean up external references.
  """
  @spec cleanup([map()], map()) :: :ok | {:error, [{String.t(), any()}]}
  def cleanup(attrs_meta, data) do
    errors =
      attrs_meta
      |> relation_attributes()
      |> Enum.reduce([], fn %{handle: handle, data_config: dc}, errs ->
        rc = dc["relation_config"] || %{}
        ref = Map.get(data, handle)

        if is_nil(ref) do
          errs
        else
          case lookup_adapter(rc) do
            nil -> errs
            adapter ->
              case adapter.delete(ref, rc) do
                :ok -> errs
                {:error, reason} -> [{handle, reason} | errs]
              end
          end
        end
      end)

    case errors do
      [] -> :ok
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  @doc "Looks up the adapter module for a relation_config's declared source."
  @spec lookup_adapter(map()) :: module() | nil
  def lookup_adapter(%{"source" => source}) when is_binary(source) do
    sources = Application.get_env(:attr_engine, :relation_sources, %{})
    Map.get(sources, source)
  end

  def lookup_adapter(_), do: nil

  # --- Private ---

  defp relation_attributes(attrs_meta) do
    Enum.filter(attrs_meta, fn meta ->
      meta[:type] == :relation || get_in(meta, [:data_config, "type"]) == "relation"
    end)
  end

  defp resolve_one(_handle, nil, _rc, acc, errs), do: {acc, errs}

  defp resolve_one(handle, ref, rc, acc, errs) do
    case lookup_adapter(rc) do
      nil ->
        {acc, [{handle, :no_adapter} | errs]}

      adapter ->
        case adapter.resolve(ref, rc) do
          {:ok, value} -> {Map.put(acc, handle, value), errs}
          {:error, reason} -> {acc, [{handle, reason} | errs]}
        end
    end
  end

  defp store_one(handle, value, rc, acc, errs) do
    case lookup_adapter(rc) do
      nil ->
        {acc, [{handle, :no_adapter} | errs]}

      adapter ->
        case adapter.store(value, rc) do
          {:ok, ref} -> {Map.put(acc, handle, ref), errs}
          {:error, reason} -> {acc, [{handle, reason} | errs]}
        end
    end
  end
end
