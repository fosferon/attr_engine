defmodule AttrEngine.Schema.Attribute do
  @moduledoc """
  Structural primitive — defines a single configurable field.

  An Attribute is a reusable building block: "text_input", "email_input", "asset",
  "select", etc. It carries default `data_config` and `ui_config` that can be
  overridden at the ASA and ASD layers.

  ## Key fields

  - `handle` — unique machine identifier, used in templates and data resolution
  - `data_config` — embedded `DataConfig`: data type, validation rules, source mapping
  - `ui_config` — embedded `UIConfig`: input type, tag, classes, edit/view modules
  - `draft_config` — staged config changes before promotion
  - `translations` — JSONB map for translatable metadata (name, description)
  - `state` — lifecycle state, used by workflows and pipelines

  ## Virtual fields

  - `sample` — preview sample value
  - `data_preview` — data configuration preview for UI
  - `ui_preview` — UI configuration preview for UI
  - `ui_state` — transient UI state (expanded, selected, etc.)
  - `easy_mode` — auto-generates handle/code/state from name

  ## Config cascade

  Attribute provides the **base layer** (layer 1) of the 4-layer cascade:
  Attribute defaults → ASA overrides → ASD instance → runtime enrichment.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias AttrEngine.Schema.Attribute.DataConfig
  alias AttrEngine.Schema.Attribute.UIConfig

  if Code.ensure_loaded?(Flop.Schema) do
    @derive {
      Flop.Schema,
      default_order: %{
        order_by: [:name],
        order_directions: [:asc, :desc]
      },
      filterable: [
        :name,
        :code,
        :handle,
        :state,
        :active,
        :system,
        :searchable,
        :sort,
        :description
      ],
      sortable: [
        :name,
        :code,
        :handle,
        :state,
        :sort
      ],
      max_limit: 1000,
      default_limit: 10,
      adapter_opts: []
    }
  end

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "attributes" do
    field :pub_id, :binary_id
    field :name, :string
    field :handle, :string
    field :code, :string
    field :description, :string
    field :state, :string

    # Config — embedded schemas
    embeds_one :data_config, DataConfig, on_replace: :update
    embeds_one :ui_config, UIConfig, on_replace: :update
    field :validations, :map, default: %{}

    # Flags
    field :active, :boolean, default: false
    field :system, :boolean, default: false
    field :searchable, :boolean, default: false
    field :exportable, :boolean, default: false
    field :importable, :boolean, default: false
    field :readonly, :boolean, default: false
    field :visible, :boolean, default: false
    field :deleted, :boolean, default: false

    # Ordering
    field :sort, :integer, default: 0

    # Multilingual — JSONB map of translatable metadata
    field :translations, :map, default: %{}

    # Draft config — staged changes before promotion
    field :draft_config, :map, default: %{}

    # Virtual fields
    field :easy_mode, :boolean, virtual: true, default: false
    field :sample, :string, virtual: true
    field :data_preview, :map, virtual: true
    field :ui_preview, :map, virtual: true
    field :ui_state, :map, virtual: true, default: %{expanded: false}

    many_to_many :attribute_sets, AttrEngine.Schema.AttributeSet,
      join_through: AttrEngine.Schema.AttributeSetAttribute,
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @cast_fields [
    :pub_id, :name, :handle, :sample, :code, :description, :state,
    :validations, :active, :system, :searchable, :exportable, :importable,
    :readonly, :visible, :deleted, :sort, :translations, :ui_state,
    :easy_mode, :draft_config
  ]

  @doc """
  Builds a changeset for attribute creation and updates.

  Handles auto-injection of handle, code, and state when easy_mode is enabled.
  Casts embedded UI and data configurations, and prevents modification of locked
  identifiers on persisted records.
  """
  def changeset(attribute, attrs) do
    attribute
    |> cast(attrs, @cast_fields)
    |> maybe_put_pub_id()
    |> validate_required([:name])
    |> maybe_cast_embed_ui_config()
    |> maybe_cast_embed_data_config()
    |> maybe_lock_identifiers()
    |> handle_easy_mode()
  end

  # --- Pub ID ---

  defp maybe_put_pub_id(%Ecto.Changeset{} = cs) do
    case fetch_field(cs, :pub_id) do
      {:data, nil} -> put_change(cs, :pub_id, Ecto.UUID.generate())
      {:changes, nil} -> put_change(cs, :pub_id, Ecto.UUID.generate())
      _ -> cs
    end
  end

  # --- Conditional embed casting ---

  defp maybe_cast_embed_ui_config(%Ecto.Changeset{} = changeset) do
    case get_field(changeset, :ui_config) do
      ui_config when is_map(ui_config) -> cast_embed(changeset, :ui_config)
      _ -> changeset
    end
  end

  defp maybe_cast_embed_data_config(%Ecto.Changeset{} = changeset) do
    case get_field(changeset, :data_config) do
      data_config when is_map(data_config) -> cast_embed(changeset, :data_config)
      _ -> changeset
    end
  end

  # --- Identifier locking ---

  defp maybe_lock_identifiers(%Ecto.Changeset{} = changeset) do
    if persisted?(changeset) do
      changeset
      |> maybe_lock_field(:handle, :lock_handle?)
      |> maybe_lock_field(:code, :lock_code?)
    else
      changeset
    end
  end

  defp maybe_lock_field(%Ecto.Changeset{} = changeset, field, lock_key) do
    if Map.has_key?(changeset.changes, field) and lock_enabled?(changeset, lock_key) do
      add_error(changeset, field, "is locked and cannot be changed")
    else
      changeset
    end
  end

  defp lock_enabled?(%Ecto.Changeset{} = changeset, lock_key) do
    case get_field(changeset, :ui_config) do
      %UIConfig{} = cfg -> Map.get(cfg, lock_key, true)
      %{} = cfg -> Map.get(cfg, lock_key, true)
      _ -> true
    end
  end

  defp persisted?(%Ecto.Changeset{} = changeset) do
    case get_field(changeset, :id) do
      nil -> false
      _ -> true
    end
  end

  # --- Easy mode: auto-generate handle, code, state from name ---

  defp handle_easy_mode(%Ecto.Changeset{} = cs) do
    case get_field(cs, :easy_mode) do
      true ->
        cs
        |> handle_injection()
        |> code_injection()
        |> state_injection()

      _ ->
        cs |> validate_required([:handle, :state])
    end
  end

  defp handle_injection(%Ecto.Changeset{valid?: false} = cs), do: cs

  defp handle_injection(changeset) do
    name = get_field(changeset, :name)

    if empty?(get_field(changeset, :handle)) do
      put_change(changeset, :handle, Slug.slugify(name))
    else
      changeset
    end
  end

  defp code_injection(%Ecto.Changeset{valid?: false} = cs), do: cs

  defp code_injection(changeset) do
    if empty?(get_field(changeset, :code)) do
      code = "ATTR-#{String.upcase(rand_string(8))}"
      put_change(changeset, :code, code)
    else
      changeset
    end
  end

  defp state_injection(%Ecto.Changeset{valid?: false} = cs), do: cs

  defp state_injection(changeset) do
    if empty?(get_field(changeset, :state)) do
      put_change(changeset, :state, "initialised")
    else
      changeset
    end
  end

  # --- Helpers ---

  defp empty?(nil), do: true
  defp empty?(""), do: true
  defp empty?(_), do: false

  defp rand_string(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode32(case: :upper, padding: false)
    |> binary_part(0, length)
  end
end
