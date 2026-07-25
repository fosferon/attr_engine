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
- A database: PostgreSQL (uses JSONB columns) or SQLite (via `ecto_sqlite3`; `:map` columns are stored as JSON TEXT). The migration generator emits adapter-appropriate DDL — see [Setup](#setup).
- Optional: [Flop](https://hex.pm/packages/flop) for paginated/filterable queries

## Installation

```elixir
def deps do
  [
    {:attr_engine, "~> 0.5"}
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

The generator picks its DDL from the configured repo's adapter: PostgreSQL by
default, SQLite when the repo uses `Ecto.Adapters.SQLite3` (`:uuid` columns
become `:string`; the `attribute_set_attributes` handle CHECK is enforced at the
application layer instead of via `ALTER TABLE ... ADD CONSTRAINT`, which SQLite
does not support). Override detection with `mix attr_engine.gen.migration --db sqlite`.

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

## What's new in v0.5

- **Render-time transforms** — declare a `transform` on any attribute's `data_config`
  to rewrite its value at resolution/render time. Ships with `redact` and `redact_secret`
  built-ins; register your own modules or functions. Transforms run automatically inside
  `Render.Block.render/4` and `Cascade.build_context/3`. See [Render-Time Transforms](#render-time-transforms).
- **Relation attributes** — a new `data_config.type = "relation"` stores an opaque ref
  in the ASD while the real value lives in an external store, reached through pluggable
  source adapters. A `ref_only` mode keeps raw secrets out of the ASD entirely.
  See [Relation Attributes](#relation-attributes).

## What's new in v0.2

- **Embedded config schemas** — `data_config` and `ui_config` are now `embeds_one` structs
  (`DataConfig`, `UIConfig`) with typed fields and validation, while remaining compatible
  with plain maps via the cascade normalizer.
- **Virtual fields** — `sample`, `data_preview`, `ui_preview`, `ui_state` for transient UI state.
- **Identifier locking** — `UIConfig` carries `lock_handle?` / `lock_code?` flags; persisted
  records reject changes to locked identifiers.
- **Flop integration** — `Attribute` derives `Flop.Schema` when Flop is available, enabling
  paginated, filtered, sorted queries out of the box.
- **Draft config** — `draft_config` field for staged configuration changes before promotion.
- **Multi-tenant** — all public APIs accept `prefix: "tenant_schema"` in opts for Postgres schema-per-tenant scoping.

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
| **Attribute** | Structural primitive — defines a field type with embedded `DataConfig` / `UIConfig`, virtual preview fields, and optional Flop filtering |
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

# Create a text attribute — v0.2+ uses embedded structs for configs
{:ok, title} =
  %Attribute{}
  |> Attribute.changeset(%{
    "name" => "Title",
    "easy_mode" => true,
    "data_config" => %{"type" => "string", "required" => true, "has_default" => false},
    "ui_config" => %{"type" => "text", "lock_handle?" => false}
  })
  |> AttrEngine.repo().insert()

# Plain maps still work — the cascade normalizer handles both
{:ok, image} =
  %Attribute{}
  |> Attribute.changeset(%{
    "name" => "Background Image",
    "easy_mode" => true,
    "data_config" => %{"type" => "binary", "required" => false, "has_default" => false},
    "ui_config" => %{"type" => "file"}
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

## Multi-Tenant Queries

For schema-per-tenant architectures, pass `prefix: "tenant_schema"` to any public API
that hits the database:

```elixir
# Cascade resolution scoped to a tenant
attrs_meta = AttrEngine.Cascade.resolve_attrs_meta(set_id, prefix: "tenant_42")

# Rendering scoped to a tenant
html = AttrEngine.Render.Block.render("hero_block", data, "en", prefix: "tenant_42")

# AttributeSet changeset with tenant-scoped uniqueness check
AttributeSet.changeset(set, attrs, prefix: "tenant_42")
```

This is fully backward compatible — omit `:prefix` and all queries run against the default schema.

## Table Prefixes

If you share a database with other applications, use `table_prefix` to namespace all AttrEngine tables:

```elixir
config :attr_engine, table_prefix: "cms_"
# Creates tables: cms_attributes, cms_attribute_sets, cms_attribute_set_attributes, etc.
```

## Render-Time Transforms

Transforms rewrite an attribute's value at resolution time, before it reaches a renderer
or API consumer. Declare one with the `transform` key in `data_config`:

```elixir
# Single transform (built-in)
data_config = %{"type" => "binary", "transform" => "redact_secret"}

# Pipeline — applied left to right
data_config = %{"type" => "string", "transform" => ["upcase", "trim"]}
```

### Built-in transforms

| Name | Effect |
|---|---|
| `"redact"` | Replaces any non-nil value with `"••••••••"`; preserves `nil` |
| `"redact_secret"` | Non-nil → `"[provided]"`, nil/empty → `"[not set]"` — for credential UIs |

### Custom transforms

Register modules (implementing `apply/2`) or functions via config:

```elixir
config :attr_engine, transforms: %{
  "currency" => MyApp.Transforms.Currency,                        # module @behaviour AttrEngine.Transform
  "upcase"   => &String.upcase/1,                                 # 1-arity function
  "prefix"   => fn value, opts -> opts["prefix"] <> value end    # 2-arity, receives data_config
}
```

```elixir
defmodule MyApp.Transforms.Currency do
  @behaviour AttrEngine.Transform

  @impl true
  def apply(value, _opts) when is_number(value) do
    :erlang.float_to_binary(value / 1.0, decimals: 2)
  end

  def apply(value, _opts), do: value
end
```

External transforms take precedence over built-ins with the same name.

### Applying transforms

Transforms run automatically during `Render.Block.render/4` and `Cascade.build_context/3`.
To apply them manually (e.g. for an API response):

```elixir
attrs_meta = AttrEngine.Cascade.resolve_attrs_meta(set_id)
transformed = AttrEngine.Transform.apply_transforms(attrs_meta, data)
```

## Relation Attributes

A relation attribute stores an opaque **ref** in the ASD while the real value lives in an
external store (a secrets vault, another service, a separate table). The engine reaches the
target through pluggable **source adapters**, so the data model stays decoupled from where
values physically live.

Declare one via `data_config`:

```elixir
data_config = %{
  "type" => "relation",
  "relation_config" => %{
    "source" => "vault",          # adapter name, looked up in the registry
    "ref_only" => true,           # value never materializes in the ASD — only the ref is stored
    "ref_key" => "my_credential"  # any adapter-specific keys are passed through
  }
}
```

### Registering source adapters

Adapters implement the `AttrEngine.Relation` behaviour (`resolve/2`, `store/2`, `delete/2`)
and are registered by name:

```elixir
config :attr_engine, relation_sources: %{
  "vault" => MyApp.Adapters.Vault,
  "users" => MyApp.Adapters.Users
}
```

```elixir
defmodule MyApp.Adapters.Vault do
  @behaviour AttrEngine.Relation

  @impl true
  def resolve(ref, _config), do: Vault.get(ref)

  @impl true
  def store(value, config) do
    name = config["ref_key"] || generate_name()
    :ok = Vault.put(name, value)
    {:ok, name}
  end

  @impl true
  def delete(ref, _config), do: Vault.delete(ref)
end
```

### Read, write, and cleanup

```elixir
attrs_meta = AttrEngine.Cascade.resolve_attrs_meta(set_id)

# WRITE — routes raw values to their stores, persists refs in the ASD
{:ok, asd_data} = AttrEngine.Relation.process_writes(attrs_meta, incoming_data)

# READ — resolves refs to values (skips ref_only by default; pass skip_ref_only: false to force)
{:ok, resolved} = AttrEngine.Relation.resolve_relations(attrs_meta, asd_data)

# CLEANUP — deletes target values when an ASD is removed
:ok = AttrEngine.Relation.cleanup(attrs_meta, asd_data)
```

### Secrets pattern

For credentials and other sensitive relations, combine `ref_only: true` with the
`redact_secret` transform. The raw value is routed to the vault on write and never stored
in the ASD; on render, the ref is masked so the frontend only ever sees `"[provided]"` or
`"[not set]"`:

```elixir
data_config = %{
  "type" => "relation",
  "transform" => "redact_secret",
  "relation_config" => %{"source" => "vault", "ref_only" => true}
}
```

## License

MIT
