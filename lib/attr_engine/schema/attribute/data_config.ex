defmodule AttrEngine.Schema.Attribute.DataConfig do
  @moduledoc """
  Embedded schema for the data-side configuration of an Attribute.

  Captures the structural contract: type, default value, required flag,
  import-source mapping, relation config, and validation rules.

  ## Fields

  - `type` — the data type identifier (e.g. `"binary"`, `"integer"`, `"relation"`)
  - `required` — whether the attribute must have a value
  - `has_default` / `default` — whether a default value exists and its shape
  - `source_column` — which source column this maps to during import
  - `relation_config` — flexible map for relation settings
    (target_type, target_set_id, matching_rules, etc.)
  - `validations` — list of validation rule maps
  - `source` — data source configuration map

  Consumers may store additional ad-hoc keys at the ASA level; those are
  merged on top by `AttrEngine.Cascade` at resolution time.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type :binary_id

  @types ~w(binary integer float boolean date time datetime map list relation)

  embedded_schema do
    field :required, :boolean
    field :type, :string, default: "binary"
    field :default, :map
    field :has_default, :boolean, default: false
    field :source_column, :string
    field :relation_config, :map
    field :validations, {:array, :map}, default: []
    field :source, :map
  end

  @cast_fields ~w(required type default has_default source_column relation_config validations source)a

  @doc "Standard changeset — validates required fields and type inclusion."
  def changeset(data_config, attrs) do
    data_config
    |> cast(attrs, @cast_fields)
    |> validate_required([:required, :type, :has_default])
    |> validate_inclusion(:type, @types)
    |> validate_default_present()
  end

  @doc "Returns the list of supported data type identifiers."
  @spec type_options() :: [{String.t(), String.t()}]
  def type_options do
    Enum.map(@types, fn t -> {String.capitalize(t), t} end)
  end

  defp validate_default_present(changeset) do
    if get_change(changeset, :has_default) == true and is_nil(get_change(changeset, :default)) do
      add_error(changeset, :default, "is required when has_default is true")
    else
      changeset
    end
  end
end
