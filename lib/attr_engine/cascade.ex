defmodule AttrEngine.Cascade do
  @moduledoc """
  4-layer config cascade resolution.

  Resolves the effective configuration for each attribute in a block by
  merging configs from all layers:

  1. **Attribute** — structural defaults (data_config, ui_config)
  2. **ASA** — semantic overrides for this set
  3. **ASD** — per-instance overrides
  4. **Runtime** — transforms, enrichments

  ## Usage

      # Get resolved attribute metadata for a block type
      attrs_meta = AttrEngine.Cascade.resolve_attrs_meta(block_type_handle)

      # Apply ASD ui_config overrides on top
      final_meta = AttrEngine.Cascade.apply_asd_overrides(attrs_meta, asd_ui_config)

      # Get the full rendering context (data + ui keys flattened)
      context = AttrEngine.Cascade.build_context(attrs_meta, data, locale)

  ## Multi-tenant (schema-per-tenant)

  All functions that hit the database accept an `opts` keyword list.
  Pass `prefix: "tenant_schema"` to scope queries to a specific
  Postgres schema:

      attrs_meta = AttrEngine.Cascade.resolve_attrs_meta(set_id, prefix: "tenant_42")
  """

  alias AttrEngine.Schema.AttributeSetAttribute

  @doc """
  Resolves the full attribute metadata for a block type, including cascaded configs.

  Returns a list of maps:

      [
        %{
          handle: "title",
          type: :string,
          localized: true,
          data_config: %{...},   # merged: Attribute → ASA
          ui_config: %{...}      # merged: Attribute → ASA
        },
        ...
      ]

  Ordered by ASA.sort.
  """
  @spec resolve_attrs_meta(integer(), keyword()) :: [map()]
  def resolve_attrs_meta(attribute_set_id, opts \\ []) do
    import Ecto.Query

    repo_opts = Keyword.take(opts, [:prefix])

    asas =
      AttributeSetAttribute
      |> where([asa], asa.attribute_set_id == ^attribute_set_id)
      |> order_by([asa], asc: asa.sort)
      |> AttrEngine.repo().all(repo_opts)
      |> AttrEngine.repo().preload(:attribute, repo_opts)

    Enum.map(asas, fn asa ->
      attr = asa.attribute

      # Layer 1 + 2: merge Attribute defaults with ASA overrides
      # Attribute configs may be embedded structs (v0.2+) or plain maps (v0.1);
      # normalize to string-keyed maps before merging with ASA plain-map overrides.
      data_config = deep_merge(normalize_config(attr.data_config), asa.data_config || %{})
      ui_config = deep_merge(normalize_config(attr.ui_config), asa.ui_config || %{})

      type =
        case data_config["type"] do
          nil -> :string
          t when is_binary(t) -> String.to_existing_atom(t)
          t when is_atom(t) -> t
        end

      %{
        handle: asa.handle || attr.handle,
        type: type,
        localized: data_config["localized"] == true,
        data_config: data_config,
        ui_config: ui_config,
        searchable: asa.searchable || attr.searchable,
        exportable: asa.exportable || attr.exportable,
        sort: asa.sort || 0
      }
    end)
  end

  @doc """
  Applies ASD (per-instance) ui_config overrides on top of resolved attrs_meta.

  `asd_ui` is keyed by attribute handle:

      %{"title" => %{"classes" => "text-center", "append" => true}}

  If `"append"` is true, string values are concatenated. Otherwise, replaced.
  """
  @spec apply_asd_overrides([map()], map() | nil) :: [map()]
  def apply_asd_overrides(attrs_meta, nil), do: attrs_meta
  def apply_asd_overrides(attrs_meta, asd_ui) when asd_ui == %{}, do: attrs_meta

  def apply_asd_overrides(attrs_meta, asd_ui) do
    Enum.map(attrs_meta, fn %{handle: handle, ui_config: ui} = meta ->
      case Map.get(asd_ui, handle) do
        nil ->
          meta

        overrides when is_map(overrides) ->
          append? = Map.get(overrides, "append", false)
          merged = merge_ui(ui, Map.delete(overrides, "append"), append?)
          %{meta | ui_config: merged}

        _ ->
          meta
      end
    end)
  end

  @doc """
  Builds a flat rendering context from resolved attrs_meta and data.

  Returns a map with:
  - Data values keyed by handle (with any declared transforms applied)
  - UI keys prefixed: `{handle}_tag`, `{handle}_class`, etc.
  - Block-level UI keys from the AttributeSet: `block_tag`, `block_class`, etc.
  """
  @spec build_context([map()], map(), map()) :: map()
  def build_context(attrs_meta, data, set_ui_config \\ %{}) do
    # Apply transforms before building context
    transformed_data = AttrEngine.Transform.apply_transforms(attrs_meta, data)

    # Data values
    data_ctx =
      Enum.reduce(attrs_meta, %{}, fn %{handle: handle}, acc ->
        Map.put(acc, handle, Map.get(transformed_data, handle))
      end)

    # Per-attribute UI keys
    ui_ctx =
      Enum.reduce(attrs_meta, %{}, fn %{handle: handle, ui_config: ui}, acc ->
        Enum.reduce(ui, acc, fn {k, v}, inner ->
          Map.put(inner, "#{handle}_#{k}", v)
        end)
      end)

    # Block-level UI keys
    block_ctx =
      Enum.reduce(set_ui_config, %{}, fn {k, v}, acc ->
        Map.put(acc, "block_#{k}", v)
      end)

    data_ctx
    |> Map.merge(ui_ctx)
    |> Map.merge(block_ctx)
  end

  # --- Private helpers ---

  # Converts an embedded struct (or nil/plain map) to a string-keyed map
  # suitable for cascade merging. Drops nil values and the embed's internal :id.
  defp normalize_config(nil), do: %{}

  defp normalize_config(%{__struct__: _} = struct) do
    struct
    |> Map.from_struct()
    |> Map.delete(:id)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end

  defp normalize_config(map) when is_map(map), do: map
  defp normalize_config(_), do: %{}

  defp deep_merge(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override, fn
      _key, v1, v2 when is_map(v1) and is_map(v2) -> deep_merge(v1, v2)
      _key, _v1, v2 -> v2
    end)
  end

  defp deep_merge(_base, override), do: override

  defp merge_ui(base, overrides, append?) do
    Enum.reduce(overrides, base, fn {key, value}, acc ->
      if append? and is_binary(value) and is_binary(Map.get(acc, key)) do
        Map.put(acc, key, String.trim("#{Map.get(acc, key)} #{value}"))
      else
        Map.put(acc, key, value)
      end
    end)
  end
end
