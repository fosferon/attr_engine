defmodule AttrEngine.Locale do
  @moduledoc """
  Multilingual value resolution for attribute data.

  AttrEngine stores localized values as JSONB maps keyed by locale:

      %{"en" => "Welcome", "el" => "Καλωσήρθατε", "de" => "Willkommen"}

  This module resolves those maps to a single value for the target locale,
  with configurable fallback behaviour.

  ## Modes

  - `:fallback` (default) — tries target locale, then default locale, then first available
  - `:strict` — returns `:__missing__` if target locale not found (for skip-block behaviour)

  ## Deep resolution

  `resolve_deep/3` recursively walks JSONB trees, resolving all localized maps
  at any nesting depth. Correctly skips rich content maps (EditorJS, Lexical)
  that happen to have locale-like keys.

  ## Usage

      data = %{"title" => %{"en" => "Hello", "el" => "Γεια"}, "count" => 42}

      AttrEngine.Locale.resolve_deep(data, "el", default_locale: "en")
      #=> %{"title" => "Γεια", "count" => 42}

      AttrEngine.Locale.resolve_deep(data, "de", default_locale: "en")
      #=> %{"title" => "Hello", "count" => 42}

      AttrEngine.Locale.resolve_deep(data, "de", mode: :strict)
      #=> %{"title" => :__missing__, "count" => 42}
  """

  @type mode :: :fallback | :strict

  # --- Single value resolution ---

  @doc """
  Resolves a single potentially-localized value for the target locale.

  ## Options

  - `:mode` — `:fallback` (default) or `:strict`
  - `:default_locale` — locale to try if target not found (fallback mode)
  - `:locales` — list of known locale keys, used to identify localized maps
  """
  @spec resolve(any(), String.t(), keyword()) :: any()
  def resolve(value, locale, opts \\ [])

  def resolve(value, locale, opts) when is_map(value) do
    mode = Keyword.get(opts, :mode, :fallback)
    default_locale = Keyword.get(opts, :default_locale)
    locales = Keyword.get(opts, :locales, [])

    if localized_map?(value, locales) do
      resolve_from_map(value, locale, default_locale, mode)
    else
      value
    end
  end

  def resolve(value, _locale, _opts), do: value

  # --- Deep recursive resolution ---

  @doc """
  Recursively resolves all localized maps in a JSONB tree.

  Walks maps and lists depth-first. Localized maps are resolved to single values.
  Rich content maps (EditorJS, Lexical) are preserved as-is.

  Same options as `resolve/3`.
  """
  @spec resolve_deep(any(), String.t(), keyword()) :: any()
  def resolve_deep(data, locale, opts \\ [])

  def resolve_deep(data, locale, opts) when is_map(data) do
    locales = Keyword.get(opts, :locales, [])

    if localized_map?(data, locales) do
      resolve(data, locale, opts)
    else
      # Skip rich content structures — they're data, not locale wrappers
      if rich_content?(data) do
        data
      else
        Map.new(data, fn {k, v} -> {k, resolve_deep(v, locale, opts)} end)
      end
    end
  end

  def resolve_deep(data, locale, opts) when is_list(data) do
    Enum.map(data, &resolve_deep(&1, locale, opts))
  end

  def resolve_deep(data, _locale, _opts), do: data

  # --- Lightweight deep resolution (no locales list) ---

  @doc """
  Simplified deep locale resolution using heuristics.

  For cases where the known locales list isn't available.
  Uses `is_localized_heuristic?/1` to detect locale maps:
  map has "en" key, size ≤ 8, all values are strings or nil.
  """
  @spec resolve_deep_heuristic(any(), String.t()) :: any()
  def resolve_deep_heuristic(data, locale) when is_map(data) do
    cond do
      rich_content?(data) ->
        data

      is_localized_heuristic?(data) ->
        data[locale] || data["en"] || ""

      true ->
        Map.new(data, fn {k, v} -> {k, resolve_deep_heuristic(v, locale)} end)
    end
  end

  def resolve_deep_heuristic(data, locale) when is_list(data) do
    Enum.map(data, &resolve_deep_heuristic(&1, locale))
  end

  def resolve_deep_heuristic(data, _locale), do: data

  # --- Missing check ---

  @doc """
  Returns true if any value in the context is `:__missing__` (strict mode artifact).
  Used to decide whether to skip rendering a block.
  """
  @spec has_missing?(any()) :: boolean()
  def has_missing?(data) when is_map(data) do
    Enum.any?(data, fn
      {_k, :__missing__} -> true
      {_k, v} when is_map(v) -> has_missing?(v)
      {_k, v} when is_list(v) -> Enum.any?(v, &has_missing?/1)
      _ -> false
    end)
  end

  def has_missing?(:__missing__), do: true
  def has_missing?(_), do: false

  @doc """
  Replaces all `:__missing__` atoms with empty strings.
  For rendering contexts that should show partial content rather than skip.
  """
  @spec replace_missing(any()) :: any()
  def replace_missing(:__missing__), do: ""

  def replace_missing(data) when is_map(data) do
    Map.new(data, fn
      {k, :__missing__} -> {k, ""}
      {k, v} -> {k, replace_missing(v)}
    end)
  end

  def replace_missing(data) when is_list(data) do
    Enum.map(data, &replace_missing/1)
  end

  def replace_missing(data), do: data

  # --- Private helpers ---

  # A map is localized if all its keys are in the known locales list
  defp localized_map?(_map, []), do: false

  defp localized_map?(map, locales) when is_list(locales) do
    keys = Map.keys(map)
    keys != [] and Enum.all?(keys, fn k -> is_binary(k) and k in locales end)
  end

  # Heuristic: has "en" key, small size, all values are strings or nil
  defp is_localized_heuristic?(%{"en" => _} = map) when map_size(map) <= 8 do
    Enum.all?(map, fn {_k, v} -> is_binary(v) or is_nil(v) end)
  end

  defp is_localized_heuristic?(_), do: false

  # Rich content structures that should NOT be treated as locale maps
  defp rich_content?(%{"root" => %{"type" => "root"}}), do: true
  defp rich_content?(%{"blocks" => blocks}) when is_list(blocks), do: true
  defp rich_content?(_), do: false

  defp resolve_from_map(map, locale, _default_locale, :strict) do
    Map.get(map, locale, :__missing__)
  end

  defp resolve_from_map(map, locale, default_locale, :fallback) do
    cond do
      Map.has_key?(map, locale) ->
        Map.get(map, locale)

      is_binary(default_locale) and Map.has_key?(map, default_locale) ->
        Map.get(map, default_locale)

      true ->
        map |> Map.values() |> List.first()
    end
  end
end
