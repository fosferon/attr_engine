defmodule AttrEngine do
  @moduledoc """
  Parameterized attribute engine for the Fosferon ecosystem.

  AttrEngine provides a schema-driven content modelling system with:

  - **Attributes** — structural primitives (text, asset, select, boolean, etc.)
  - **AttributeSets** — named groups of attributes forming a reusable shape
  - **ASA (AttributeSetAttribute)** — join table carrying semantic identity and config overrides
  - **ASD (AttributeSetData)** — JSONB content instances with per-instance overrides
  - **4-layer config cascade** — Attribute defaults → ASA overrides → ASD instance → runtime enrichment
  - **DAG composition** — AttributeSet trees with includes/extends/overrides
  - **Multilingual resolution** — field-level locale maps with strict/fallback modes
  - **Pluggable rendering** — HTML, JSON envelopes, or custom output

  ## Configuration

      config :attr_engine,
        repo: MyApp.Repo,
        table_prefix: nil  # optional, e.g. "cms_" or "ac_"

  ## Quick start

      # Generate migrations
      mix attr_engine.gen.migration

      # Use schemas
      alias AttrEngine.Schema.{Attribute, AttributeSet, AttributeSetData}

      # Resolve locale
      AttrEngine.Locale.resolve(data, "el", default_locale: "en", mode: :fallback)

      # Render a block
      AttrEngine.Render.render_block(block_type_handle, data, locale)
  """

  @doc "Returns the configured Ecto repo."
  def repo do
    Application.fetch_env!(:attr_engine, :repo)
  end

  @doc "Returns the configured table prefix, or nil."
  def table_prefix do
    Application.get_env(:attr_engine, :table_prefix)
  end

  @doc "Returns the prefixed table name."
  def table_name(base) do
    case table_prefix() do
      nil -> base
      prefix -> "#{prefix}#{base}"
    end
  end
end
