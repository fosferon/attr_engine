# AttrEngine

Schema-driven content modelling engine for Elixir.

Define attributes at runtime, compose them into sets via a DAG, resolve locales,
and render to HTML or structured JSON — all through a 4-layer configuration cascade
that keeps base schemas DRY while allowing per-instance customization.

## When to use this

AttrEngine is for applications where **the data shape is defined at runtime, not compile time**:

- CMS block systems (headless or traditional)
- Entity attribute systems (CRM contacts, product variants, custom fields)
- Form builders with dynamic schemas
- Any system needing user-configurable content structures with multilingual support

## Prerequisites

- Elixir >= 1.19
- Ecto >= 3.10 with a configured repo
- PostgreSQL (uses JSONB columns)

## Installation

```elixir
def deps do
  [
    {:attr_engine, "~> 0.1"}
  ]
end
```

## Setup

### 1. Configure the repo

```elixir
# config/config.exs
config :attr_engine,
  repo: MyApp.Repo,
  table_prefix: nil  # optional: namespace tables, e.g. "cms_"
```

### 2. Generate and run migrations

```bash
mix attr_engine.gen.migration
mix ecto.migrate
```

This creates 9 tables. See [Data Model](#data-model) below for the full schema.

### 3. Optional: configure renderers

```elixir
config :attr_engine,
  # Rich text renderer for :editorjs type attributes
  rich_text_renderer: MyApp.EditorJSRenderer,

  # Custom attribute type renderers
  custom_renderers: %{
    sequence: MyApp.SequenceRenderer,
    audio: MyApp.AudioRenderer
  },

  # Component blocks that bypass the cascade and render directly
  component_blocks: %{
    "superhero" => MyApp.Components.Superhero
  }
```

## Data Model

```
┌─────────────┐     ┌───────────────────┐     ┌──────────────┐
│  Attribute   │────<│  AttributeSetAttr  │>────│ AttributeSet │
│  (primitive) │     │  (ASA — join +     │     │  (group)     │
│              │     │   overrides)       │     │              │
└─────────────┘     └───────────────────┘     └──────┬───────┘
                                                      │
                                              ┌───────┴────────┐
                                              │ AttributeSetTree│
                                              │ (DAG — include, │
                                              │  extend, override)│
                                              └────────────────┘
                                                      │
                                              ┌───────┴────────┐
                                              │ AttributeSetData│
                                              │ (ASD — content  │
                                              │  instances)     │
                                              └────────────────┘
                                                      │
                                              ┌───────┴────────┐
                                              │  BlockType →   │
                                              │  Block →       │
                                              │  BlockTree     │
                                              │ (rendering)    │
                                              └────────────────┘
```

### The core entities

| Entity | Role |
|---|---|
| **Attribute** | Structural primitive — defines a field type (`:string`, `:asset`, `:boolean`, etc.) with default `data_config` and `ui_config` |
| **AttributeSet** | Named group of attributes — a reusable content shape (e.g., "Hero Banner", "Contact Card") |
| **ASA** (AttributeSetAttribute) | Join table carrying semantic identity + per-usage config overrides |
| **ASD** (AttributeSetData) | A content instance — JSONB data owned by a set, with per-instance ui_config overrides |
| **BlockType** | Links an AttributeSet to a rendering handle (e.g., `"heading_block"`) |
| **Block** | A positioned instance of a BlockType within a tree |
| **AttributeSetTree** | DAG edges between sets — compose via `include`, `extend`, or `override` |

## The 4-Layer Config Cascade

Every attribute's effective configuration is resolved by merging four layers:

```
Layer 1: Attribute defaults (data type, base ui_config)
    ↓ merge
Layer 2: ASA overrides (per-set semantic tweaks)
    ↓ merge
Layer 3: ASD overrides (per-instance customization)
    ↓ merge
Layer 4: Runtime enrichment (transforms, computed fields)
    ↓
Final resolved config → render
```

This means you define a base "Title" attribute once, then override its tag, classes,
or validation per AttributeSet (layer 2) and even per content instance (layer 3).

## End-to-End Example

### Step 1: Create attributes

```elixir
alias AttrEngine.Schema.{Attribute, AttributeSet, AttributeSetData}
alias AttrEngine.Schema.{BlockType, Block}

# Create a text attribute
{:ok, title} =
  %Attribute{}
  |> Attribute.changeset(%{
    "name" => "Title",
    "easy_mode" => true,  # auto-generates handle, code, state
    "data_config" => %{"type" => "string", "localized" => true},
    "ui_config" => %{"tag" => "h2", "classes" => "text-2xl font-bold"}
  })
  |> AttrEngine.repo().insert()

# Create an image attribute
{:ok, image} =
  %Attribute{}
  |> Attribute.changeset(%{
    "name" => "Background Image",
    "easy_mode" => true,
    "data_config" => %{"type" => "asset"},
    "ui_config" => %{"classes" => "w-full hero-bg"}
  })
  |> AttrEngine.repo().insert()
```

### Step 2: Create an attribute set and attach attributes

```elixir
{:ok, hero_set} =
  %AttributeSet{}
  |> AttributeSet.changeset(%{
    "name" => "Hero Banner",
    "handle" => "hero_banner",
    "easy_mode" => true
  })
  |> AttrEngine.repo().insert()

# Attach attributes with overrides (layer 2)
# The ASA join carries sort order and per-usage config
hero_set
|> AttrEngine.repo().preload(:attributes)
|> Ecto.Changeset.change()
|> Ecto.Changeset.put_assoc(:attributes, [title, image])
|> AttrEngine.repo().update()
```

### Step 3: Create a block type and content data

```elixir
{:ok, block_type} =
  %BlockType{}
  |> BlockType.changeset(%{
    "handle" => "hero_block",
    "name" => "Hero Block",
    "attribute_set_id" => hero_set.id
  })
  |> AttrEngine.repo().insert()

# Create a content instance with multilingual data
{:ok, data} =
  %AttributeSetData{}
  |> AttributeSetData.changeset(%{
    "attribute_set_id" => hero_set.id,
    "data" => %{
      "title" => %{"en" => "Welcome", "el" => "Καλωσήρθατε"},
      "background_image" => %{"url" => "/images/hero.jpg", "alt" => "Hero"}
    }
  })
  |> AttrEngine.repo().insert()
```

### Step 4: Resolve locale and render

```elixir
# Resolve the cascade for this block type's attribute set
attrs_meta = AttrEngine.Cascade.resolve_attrs_meta(hero_set.id)

# Resolve locale on the data
resolved_data = AttrEngine.Locale.resolve_deep_heuristic(data.data, "el")
# => %{"title" => "Καλωσήρθατε", "background_image" => %{"url" => "/images/hero.jpg", ...}}

# Render to HTML
html = AttrEngine.Render.Block.render("hero_block", data.data, "el")
# => <section id="hero_block-..." data-block-type="hero_block">
#      <h2 class="text-2xl font-bold">Καλωσήρθατε</h2>
#      <img src="/images/hero.jpg" alt="Hero" class="w-full hero-bg" loading="lazy" />
#    </section>

# Or render to a structured envelope for JS/SPA frontends
envelope = AttrEngine.Render.Block.render("hero_block", data.data, "el", mode: :envelope)
# => %{type: "hero_block", data: %{...}, attrs: [...], container: %{...}}
```

## DAG Composition

Attribute sets can be composed into hierarchies via `AttributeSetTree`:

```elixir
# Create a base "Content Block" set
# ... (with title, body, image attributes)

# Create a specialised "Article Block" that extends it
# ... (adds author, published_at attributes)

# Link them
%AttrEngine.Tree.AttributeSetTree{}
|> AttrEngine.Tree.AttributeSetTree.changeset(%{
  ancestor: base_set.id,
  descendant: article_set.id,
  composition_type: "extends",       # includes | extends | overrides
  merge_strategy: "child_wins",      # parent_wins | child_wins | merge
  inheritance: true
})
|> AttrEngine.repo().insert()
```

**Composition types:**
- `includes` — child attributes are added to parent
- `extends` — child specialises parent
- `overrides` — explicit per-handle override via `override_config` map

## Multilingual Resolution

Attributes marked as `localized: true` store values as locale-keyed maps:

```elixir
data = %{
  "title" => %{"en" => "Hello", "el" => "Γεια", "de" => "Hallo"},
  "count" => 42,
  "body" => %{"root" => %{"type" => "root", "children" => [...]}}  # rich content preserved
}

# Strict mode — returns :__missing__ for unavailable locales
AttrEngine.Locale.resolve_deep(data, "fr", locales: ["en", "el", "de"], mode: :strict)
# => %{"title" => :__missing__, "count" => 42, "body" => %{...}}

# Fallback mode — falls back to default locale, then first available
AttrEngine.Locale.resolve_deep(data, "fr", locales: ["en", "el", "de"], default_locale: "en")
# => %{"title" => "Hello", "count" => 42, "body" => %{...}}

# Heuristic mode — no locales list needed, detects locale maps automatically
AttrEngine.Locale.resolve_deep_heuristic(data, "el")
# => %{"title" => "Γεια", "count" => 42, "body" => %{...}}
```

Rich content structures (EditorJS, Lexical) are automatically detected and preserved as-is.

## Rendering

### HTML rendering

```elixir
# Renders through the cascade, resolves locale, wraps in a container section
html = AttrEngine.Render.Block.render("heading_block", data, "en")
```

Supported attribute types for HTML: `:string`, `:text`, `:asset`, `:boolean`, `:select`, `:number`, `:integer`, `:editorjs`, `:json`

Custom types can be added via the `custom_renderers` config.

### Envelope rendering

```elixir
# Returns structured data for JS frontends, animation layers, or API responses
envelope = AttrEngine.Render.Block.render("piece", data, "en", mode: :envelope)
# => %{type: "piece", data: %{...}, attrs: [%{handle: ..., type: ..., ui_config: ...}], container: %{...}}
```

### Component blocks

For block types that need full control over rendering (bypassing the cascade):

```elixir
config :attr_engine,
  component_blocks: %{
    "superhero" => MyApp.Components.Superhero
  }
```

Component modules must implement `render(data, locale) :: String.t()`.

## Table Prefixes

If you share a database with other applications, use `table_prefix` to namespace all AttrEngine tables:

```elixir
config :attr_engine, table_prefix: "cms_"
# Creates tables: cms_attributes, cms_attribute_sets, cms_attribute_set_attributes, etc.
```

## License

MIT
