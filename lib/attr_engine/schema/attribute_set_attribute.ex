defmodule AttrEngine.Schema.AttributeSetAttribute do
  @moduledoc """
  Join table: links an Attribute to an AttributeSet with semantic identity.

  The ASA is where a generic structural primitive (e.g. "text_input") becomes
  a named field with context (e.g. "title" in one set, "legend" in another).

  ## Multi-handle support (v0.3.0+)

  A single Attribute can appear multiple times within the same AttributeSet,
  distinguished by `handle`. This enables structural primitives (string,
  integer, currency, etc.) to be reused across named fields:

      # Two ASAs in the same set, both pointing at the "string" Attribute
      %ASA{handle: "first_name", attribute_id: string_attr_id, attribute_set_id: set_id}
      %ASA{handle: "last_name",  attribute_id: string_attr_id, attribute_set_id: set_id}

  The uniqueness invariant is `(attribute_set_id, handle)` — each handle
  appears at most once per set. Handle is required and must be non-empty.

  ## Config cascade — Layer 2

  ASA carries its own `data_config` and `ui_config` that override the parent
  Attribute's defaults. The full cascade:

  1. Attribute.data_config / ui_config (structural defaults)
  2. **ASA.data_config / ui_config** (semantic overrides) ← this layer
  3. ASD.ui_config (per-instance overrides)
  4. Runtime enrichment (PG functions, transforms)

  ## Key fields

  - `handle` — the semantic name this attribute takes in this set (required, unique per set)
  - `data_config` — type-specific config: `%{"type" => "string", "localized" => true}`
  - `ui_config` — presentation overrides: `%{"tag" => "h2", "classes" => "..."}`
  - `sort` — position within the set
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "attribute_set_attributes" do
    field :name, :string
    field :handle, :string
    field :code, :string
    field :description, :string
    field :state, :string

    # Config — overrides Attribute defaults
    field :data_config, :map, default: %{}
    field :ui_config, :map, default: %{}
    field :validations, :map, default: %{}

    # Flags — can narrow parent Attribute's flags
    field :active, :boolean, default: false
    field :system, :boolean, default: false
    field :searchable, :boolean, default: false
    field :exportable, :boolean, default: false
    field :importable, :boolean, default: false
    field :readonly, :boolean, default: false
    field :visible, :boolean, default: false
    field :deleted, :boolean, default: false

    # Ordering within the set
    field :sort, :integer, default: 0

    # Multilingual metadata
    field :translations, :map, default: %{}

    belongs_to :attribute_set, AttrEngine.Schema.AttributeSet,
      foreign_key: :attribute_set_id

    belongs_to :attribute, AttrEngine.Schema.Attribute,
      foreign_key: :attribute_id

    timestamps(type: :utc_datetime)
  end

  @cast_fields [
    :name, :handle, :code, :description, :state,
    :data_config, :ui_config, :validations,
    :active, :system, :searchable, :exportable, :importable,
    :readonly, :visible, :deleted, :sort, :translations,
    :attribute_set_id, :attribute_id
  ]

  @doc "Standard changeset — requires handle and both foreign keys."
  def changeset(asa, attrs) do
    asa
    |> cast(attrs, @cast_fields)
    |> validate_required([:handle, :attribute_set_id, :attribute_id])
    |> validate_handle_non_empty()
    |> unique_constraint([:attribute_set_id, :handle],
      name: :attribute_set_attributes_unique_set_handle,
      message: "handle already exists in this attribute set"
    )
  end

  defp validate_handle_non_empty(changeset) do
    validate_change(changeset, :handle, fn :handle, handle ->
      if String.trim(handle) == "" do
        [handle: "must not be empty"]
      else
        []
      end
    end)
  end
end
