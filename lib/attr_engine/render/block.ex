defmodule AttrEngine.Render.Block do
  @moduledoc """
  Renders a complete block from its type, data, and locale.

  Composes the 4-layer cascade, resolves locale, renders each attribute
  via `AttrEngine.Render.Attr`, and wraps in a container.

  ## Rendering modes

  - **HTML** (default) — renders to HTML string via Attr.html/3
  - **Envelope** — returns a structured map for JS/animation layers

  Host apps can override rendering by registering component modules:

      config :attr_engine, component_blocks: %{
        "superhero" => MyApp.Components.Superhero,
        "piece" => ArtistCircle.PieceRenderer
      }

  Component modules must implement `render(data, locale) :: String.t()`.

  ## Block type aliases

  Handles normalization of common aliases:

      "image" => "image_block"
      "heading-block" => "heading_block"
  """

  alias AttrEngine.{Cascade, Locale}
  alias AttrEngine.Render.Attr, as: RenderAttr
  alias AttrEngine.Schema.BlockType

  @default_aliases %{
    "image" => "image_block",
    "rich_text" => "rich_text_block",
    "heading-block" => "heading_block",
    "grid-block" => "grid_block",
    "flex-grid" => "flex_grid",
    "content-rich" => "content_rich",
    "content-image" => "content_image"
  }

  @doc """
  Renders a block by its type handle.

  Resolves the block type from DB, loads attribute metadata via the cascade,
  resolves locale on the data, and composes HTML.

  ## Options

  - `:asd_ui_config` — per-instance ui_config overrides (layer 3)
  - `:mode` — `:html` (default) or `:envelope`
  - `:prefix` — Postgres schema prefix for multi-tenant query scoping
  """
  @spec render(String.t(), map(), String.t(), keyword()) :: String.t() | map()
  def render(block_type_handle, data, locale, opts \\ []) do
    aliases = Application.get_env(:attr_engine, :block_type_aliases, @default_aliases)
    normalized = Map.get(aliases, block_type_handle, block_type_handle)

    # Check for component blocks first
    components = Application.get_env(:attr_engine, :component_blocks, %{})

    case Map.get(components, normalized) do
      nil ->
        render_via_cascade(normalized, data, locale, opts)

      component_mod ->
        component_mod.render(data, locale)
    end
  end

  @doc """
  Returns true if the handle is a registered component block.
  """
  def component_block?(handle) do
    components = Application.get_env(:attr_engine, :component_blocks, %{})
    Map.has_key?(components, handle)
  end

  # --- Private: cascade-based rendering ---

  defp render_via_cascade(handle, data, locale, opts) do
    import Ecto.Query

    repo_opts = Keyword.take(opts, [:prefix])

    block_type =
      BlockType
      |> where([bt], bt.handle == ^handle and bt.deleted == false)
      |> limit(1)
      |> AttrEngine.repo().one(repo_opts)
      |> AttrEngine.repo().preload(:attribute_set, repo_opts)

    case block_type do
      nil -> ""
      bt -> render_from_block_type(bt, data, locale, opts)
    end
  end

  defp render_from_block_type(block_type, data, locale, opts) do
    asd_ui = Keyword.get(opts, :asd_ui_config, %{})
    mode = Keyword.get(opts, :mode, :html)

    # Resolve attrs metadata via cascade (layers 1+2)
    repo_opts = Keyword.take(opts, [:prefix])
    attrs_meta = Cascade.resolve_attrs_meta(block_type.attribute_set.id, repo_opts)

    # Apply ASD overrides (layer 3)
    attrs_meta = Cascade.apply_asd_overrides(attrs_meta, asd_ui)

    # Resolve locale on data
    resolved_data = Locale.resolve_deep_heuristic(data, locale)

    # Enrich ui_configs from sibling data (tag_from, class_from)
    attrs_meta = enrich_ui_configs(attrs_meta, resolved_data)

    set_ui_config = block_type.attribute_set.ui_config || %{}

    case mode do
      :envelope ->
        build_envelope(block_type, attrs_meta, resolved_data, set_ui_config)

      _ ->
        render_html(block_type, attrs_meta, resolved_data, set_ui_config)
    end
  end

  defp render_html(block_type, attrs_meta, data, set_ui_config) do
    attr_html =
      attrs_meta
      |> Enum.map(fn %{handle: handle, type: type, ui_config: ui_config} ->
        value = Map.get(data, handle)
        RenderAttr.html(type, ui_config, value)
      end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    wrap_block(block_type.handle, attr_html, set_ui_config)
  end

  defp build_envelope(block_type, attrs_meta, data, set_ui_config) do
    %{
      type: block_type.handle,
      data: data,
      attrs: Enum.map(attrs_meta, fn m -> Map.take(m, [:handle, :type, :ui_config]) end),
      container: set_ui_config
    }
  end

  defp wrap_block(_handle, "", _set_ui_config), do: ""

  defp wrap_block(handle, inner, set_ui_config) do
    tag = Map.get(set_ui_config, "tag", "section")
    id = Map.get(set_ui_config, "id", "#{handle}-#{unique_suffix()}")
    class = Map.get(set_ui_config, "class", "")
    style = Map.get(set_ui_config, "style", "")

    id_attr = ~s( id="#{id}")
    class_attr = if class != "", do: ~s( class="#{class}"), else: ""
    style_attr = if style != "", do: ~s( style="#{style}"), else: ""

    ~s(<#{tag}#{id_attr}#{class_attr}#{style_attr} data-block-type="#{handle}">\n#{inner}\n</#{tag}>)
  end

  # --- UI config enrichment from sibling data ---

  defp enrich_ui_configs(attrs_meta, data) do
    Enum.map(attrs_meta, fn %{data_config: dc, ui_config: ui} = meta ->
      ui =
        ui
        |> maybe_override_tag(dc, data)
        |> maybe_override_classes(dc, data)

      %{meta | ui_config: ui}
    end)
  end

  defp maybe_override_tag(ui, %{"tag_from" => field}, data) when is_binary(field) do
    case Map.get(data, field) do
      tag when tag in ~w(h1 h2 h3 h4 h5 h6 p div span) -> Map.put(ui, "tag", tag)
      _ -> ui
    end
  end

  defp maybe_override_tag(ui, _, _), do: ui

  defp maybe_override_classes(ui, %{"class_from" => %{"field" => field, "prefix" => prefix}}, data) do
    case Map.get(data, field) do
      val when is_binary(val) ->
        existing = Map.get(ui, "classes", "")
        Map.put(ui, "classes", String.trim("#{prefix}#{val} #{existing}"))

      _ ->
        ui
    end
  end

  defp maybe_override_classes(ui, _, _), do: ui

  defp unique_suffix do
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end
end
