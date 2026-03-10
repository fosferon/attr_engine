# AttrEngine

Parameterized attribute engine for the Fosferon ecosystem.

Schema-driven content modelling with a 4-layer config cascade, DAG composition,
multilingual resolution, and pluggable rendering.

## What it does

AttrEngine provides the foundational building blocks for parameterized content:

- **Attributes** — structural primitives (text, asset, select, boolean, etc.)
- **AttributeSets** — named groups of attributes forming a reusable shape
- **AttributeSetAttribute (ASA)** — join table with semantic identity + config overrides
- **AttributeSetData (ASD)** — JSONB content instances with per-instance overrides
- **BlockType / Block / BlockTree** — composable rendering units
- **4-layer config cascade** — Attribute → ASA → ASD → Runtime
- **DAG composition** — include, extend, override between attribute sets
- **Multilingual** — field-level locale maps with strict/fallback resolution
- **Pluggable rendering** — HTML, JSON envelopes, or custom output

## Consumers

| Project | Use case |
|---------|----------|
| **MOBuS CMS** | CMS blocks — heading, hero, gallery, content sections |
| **MOBuS Platform** | Entity schemas — custom attributes on contacts, tasks, assets |
| **ArtistCircle.tv** | Pieces — artwork with layered presentation parameters |

## Installation

```elixir
def deps do
  [
    {:attr_engine, github: "fosferon/attr_engine"}
  ]
end
```

## Configuration

```elixir
# config/config.exs
config :attr_engine,
  repo: MyApp.Repo,
  table_prefix: nil  # optional: "cms_", "ac_", etc.

# Optional: rich text renderer for :editorjs type
config :attr_engine,
  rich_text_renderer: MyApp.EditorJSRenderer

# Optional: custom attribute types
config :attr_engine,
  custom_renderers: %{
    sequence: MyApp.SequenceRenderer,
    audio: MyApp.AudioRenderer
  }

# Optional: component blocks (bypass cascade, render directly)
config :attr_engine,
  component_blocks: %{
    "superhero" => MyApp.Components.Superhero,
    "piece" => ArtistCircle.PieceRenderer
  }
```

## Migration

```bash
mix attr_engine.gen.migration
mix ecto.migrate
```

## Usage

### Schemas

```elixir
alias AttrEngine.Schema.{Attribute, AttributeSet, AttributeSetAttribute, AttributeSetData}

# Create an attribute with easy_mode
Attribute.changeset(%Attribute{}, %{
  "name" => "Title",
  "easy_mode" => true,
  "data_config" => %{"type" => "string", "localized" => true},
  "ui_config" => %{"tag" => "h2", "classes" => "text-2xl font-bold"}
})
```

### Locale resolution

```elixir
data = %{
  "title" => %{"en" => "Hello", "el" => "Γεια", "de" => "Hallo"},
  "count" => 42,
  "body" => %{"root" => %{"type" => "root", "children" => [...]}}
}

# With known locales
AttrEngine.Locale.resolve_deep(data, "el",
  locales: ["en", "el", "de"],
  default_locale: "en"
)
#=> %{"title" => "Γεια", "count" => 42, "body" => %{"root" => ...}}

# Heuristic (no locales list)
AttrEngine.Locale.resolve_deep_heuristic(data, "el")
#=> same result
```

### Cascade

```elixir
# Resolve effective config for all attributes in a set
attrs_meta = AttrEngine.Cascade.resolve_attrs_meta(attribute_set_id)

# Apply per-instance overrides
attrs_meta = AttrEngine.Cascade.apply_asd_overrides(attrs_meta, %{
  "title" => %{"classes" => "text-center", "append" => true}
})

# Build flat Mustache-compatible context
context = AttrEngine.Cascade.build_context(attrs_meta, data, set_ui_config)
```

### Rendering

```elixir
# Render to HTML
html = AttrEngine.Render.Block.render("heading_block", data, "en")

# Render to data envelope (for JS/animation)
envelope = AttrEngine.Render.Block.render("piece", data, "en", mode: :envelope)
```

## Architecture

```
Attribute (layer 1: structural defaults)
    ↓
AttributeSetAttribute (layer 2: semantic overrides)
    ↓
AttributeSetData (layer 3: per-instance overrides)
    ↓
Runtime enrichment (layer 4: transforms, PG functions)
    ↓
Render.Attr / Render.Block → HTML or envelope
```

## License

MIT
