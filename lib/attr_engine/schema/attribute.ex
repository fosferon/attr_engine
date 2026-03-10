defmodule AttrEngine.Schema.Attribute do
  @moduledoc """
  Structural primitive — defines a single configurable field.

  An Attribute is a reusable building block: "text_input", "email_input", "asset",
  "select", etc. It carries default `data_config` and `ui_config` that can be
  overridden at the ASA and ASD layers.

  ## Key fields

  - `handle` — unique machine identifier, used in templates and data resolution
  - `data_config` — data type, validation rules, source mapping, relation config
  - `ui_config` — presentation: input type, tag, classes, edit/view modules
  - `translations` — JSONB map for translatable metadata (name, description)
  - `state` — lifecycle state, used by workflows and pipelines

  ## Config cascade

  Attribute provides the **base layer** (layer 1) of the 4-layer cascade:
  Attribute defaults → ASA overrides → ASD instance → runtime enrichment.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "attributes" do
    field :pub_id, :binary_id
    field :name, :string
    field :handle, :string
    field :code, :string
    field :description, :string
    field :state, :string

    # Config
    field :data_config, :map, default: %{}
    field :ui_config, :map, default: %{}
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
    # e.g. %{"name" => %{"en" => "Title", "el" => "Τίτλος"}, "description" => %{...}}
    field :translations, :map, default: %{}

    # Easy mode — virtual, auto-generates handle/code/state from name
    field :easy_mode, :boolean, virtual: true, default: false

    many_to_many :attribute_sets, AttrEngine.Schema.AttributeSet,
      join_through: AttrEngine.Schema.AttributeSetAttribute,
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @cast_fields [
    :pub_id, :name, :handle, :code, :description, :state,
    :data_config, :ui_config, :validations,
    :active, :system, :searchable, :exportable, :importable,
    :readonly, :visible, :deleted, :sort, :translations, :easy_mode
  ]

  @doc "Standard changeset — validates required fields, supports easy_mode."
  def changeset(attribute, attrs) do
    attribute
    |> cast(attrs, @cast_fields)
    |> maybe_put_pub_id()
    |> validate_required([:name])
    |> handle_easy_mode()
  end

  # --- Easy mode: auto-generate handle, code, state from name ---

  defp handle_easy_mode(%Ecto.Changeset{} = cs) do
    if get_field(cs, :easy_mode) do
      cs
      |> maybe_generate_handle()
      |> maybe_generate_code()
      |> maybe_set_state()
    else
      cs |> validate_required([:handle, :state])
    end
  end

  defp maybe_generate_handle(cs) do
    case {get_field(cs, :handle), get_change(cs, :name)} do
      {nil, name} when is_binary(name) ->
        put_change(cs, :handle, Slug.slugify(name, separator: ?_))

      {"", name} when is_binary(name) ->
        put_change(cs, :handle, Slug.slugify(name, separator: ?_))

      _ ->
        cs
    end
  end

  defp maybe_generate_code(cs) do
    case get_field(cs, :code) do
      nil ->
        handle = get_field(cs, :handle) || ""
        put_change(cs, :code, String.upcase(handle))

      "" ->
        handle = get_field(cs, :handle) || ""
        put_change(cs, :code, String.upcase(handle))

      _ ->
        cs
    end
  end

  defp maybe_set_state(cs) do
    case get_field(cs, :state) do
      nil -> put_change(cs, :state, "initialised")
      "" -> put_change(cs, :state, "initialised")
      _ -> cs
    end
  end

  defp maybe_put_pub_id(cs) do
    case fetch_field(cs, :pub_id) do
      {:data, nil} -> put_change(cs, :pub_id, Ecto.UUID.generate())
      {:changes, nil} -> put_change(cs, :pub_id, Ecto.UUID.generate())
      _ -> cs
    end
  end
end
