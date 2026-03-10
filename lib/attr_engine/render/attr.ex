defmodule AttrEngine.Render.Attr do
  @moduledoc """
  Renders individual attributes to HTML based on type and ui_config.

  Pure functions — no DB calls, no side effects. Pattern-matched on type atom.

  ## Supported types

  - `:string` — text wrapped in tag (default: span)
  - `:select` — same as string (value already resolved)
  - `:number` / `:integer` — number as text in tag
  - `:boolean` — renders tag when true, empty when false
  - `:text` — longer content as raw HTML in tag (default: div)
  - `:asset` — renders as `<img>` tag from asset map or URL
  - `:editorjs` — delegates to EditorJS/Lexical renderer (via callback)
  - `:json` — not directly renderable, returns empty

  ## ui_config keys

  - `"tag"` — HTML tag to wrap in (default varies by type)
  - `"classes"` — CSS classes
  - `"custom_style"` — inline style string

  ## Extension

  Host apps can register custom type renderers:

      config :attr_engine, custom_renderers: %{
        sequence: MyApp.SequenceRenderer
      }

  Custom renderers must implement `render(ui_config, value) :: String.t()`.
  """

  # --- Nil / empty ---
  def html(_type, _ui_config, nil), do: ""
  def html(_type, _ui_config, ""), do: ""

  # --- String ---
  def html(:string, ui_config, value) when is_binary(value) do
    wrap(escape(value), ui_config, "span")
  end

  # --- Select ---
  def html(:select, ui_config, value) when is_binary(value) do
    wrap(escape(value), ui_config, "span")
  end

  # --- Number ---
  def html(:number, ui_config, value) when is_number(value) do
    wrap(to_string(value), ui_config, "span")
  end

  def html(:integer, ui_config, value) when is_integer(value) do
    wrap(to_string(value), ui_config, "span")
  end

  # --- Boolean ---
  def html(:boolean, _ui_config, false), do: ""
  def html(:boolean, _ui_config, nil), do: ""

  def html(:boolean, ui_config, true) do
    tag = Map.get(ui_config, "tag", "span")
    attrs = build_attrs(ui_config)
    "<#{tag}#{attrs}></#{tag}>"
  end

  # --- Text (raw HTML) ---
  def html(:text, ui_config, value) when is_binary(value) do
    wrap(value, ui_config, "div")
  end

  # --- Asset (image) ---
  def html(:asset, ui_config, %{"url" => url} = asset) do
    alt = Map.get(asset, "alt", "")
    classes = Map.get(ui_config, "classes", "")
    style = Map.get(ui_config, "custom_style", "")

    class_attr = if classes != "", do: ~s( class="#{classes}"), else: ""
    style_attr = if style != "", do: ~s( style="#{style}"), else: ""

    ~s(<img src="#{url}" alt="#{escape(alt)}"#{class_attr}#{style_attr} loading="lazy" />)
  end

  def html(:asset, ui_config, url) when is_binary(url) do
    html(:asset, ui_config, %{"url" => url})
  end

  # --- JSON — not directly renderable ---
  def html(:json, _ui_config, _value), do: ""

  # --- Rich text: EditorJS / Lexical ---
  # Delegate to host app's renderer via callback
  def html(:editorjs, ui_config, value) when is_map(value) do
    case rich_text_renderer() do
      nil -> ""
      renderer ->
        case renderer.render(value) do
          {:ok, rendered} -> wrap(rendered, ui_config, "div")
          _ -> ""
        end
    end
  end

  # --- Catch-all: try custom renderers, then coerce to string ---
  def html(type, ui_config, value) do
    case custom_renderer(type) do
      nil -> wrap(escape(to_string(value)), ui_config, "span")
      renderer -> renderer.render(ui_config, value)
    end
  end

  # --- Helpers ---

  defp wrap(content, ui_config, default_tag) do
    tag = Map.get(ui_config, "tag", default_tag)
    attrs = build_attrs(ui_config)
    "<#{tag}#{attrs}>#{content}</#{tag}>"
  end

  defp build_attrs(ui_config) do
    classes = Map.get(ui_config, "classes", "")
    style = Map.get(ui_config, "custom_style", "")

    class_attr = if classes != "", do: ~s( class="#{classes}"), else: ""
    style_attr = if style != "", do: ~s( style="#{style}"), else: ""

    "#{class_attr}#{style_attr}"
  end

  defp escape(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp escape(value), do: escape(to_string(value))

  defp rich_text_renderer do
    Application.get_env(:attr_engine, :rich_text_renderer)
  end

  defp custom_renderer(type) do
    renderers = Application.get_env(:attr_engine, :custom_renderers, %{})
    Map.get(renderers, type)
  end
end
