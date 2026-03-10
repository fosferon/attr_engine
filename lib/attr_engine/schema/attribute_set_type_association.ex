defmodule AttrEngine.Schema.AttributeSetTypeAssociation do
  @moduledoc """
  Links AttributeSets to external type classifications.

  Allows the host app to classify attribute sets by purpose:
  "CMS block definition", "entity schema", "piece", "gallery", etc.

  The `type_id` references whatever taxonomy/type system the host app uses.
  AttrEngine doesn't own the Type schema — it just stores the foreign key.

  ## Primary flag

  Each AttributeSet can have one type marked as `primary: true` to identify
  its main classification when it belongs to multiple types.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  schema "attribute_set_type_associations" do
    field :attribute_set_id, :id, primary_key: true
    field :type_id, :binary_id, primary_key: true
    field :primary, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @cast_fields [:attribute_set_id, :type_id, :primary]

  def changeset(assoc, attrs) do
    assoc
    |> cast(attrs, @cast_fields)
    |> validate_required([:attribute_set_id, :type_id])
  end
end
