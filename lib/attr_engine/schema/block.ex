defmodule AttrEngine.Schema.Block do
  @moduledoc """
  A content instance — binds a BlockType to its data (ASD).

  A Block is the concrete thing: a rendered heading, a piece of artwork,
  a content section. It references a BlockType (shape) and an ASD (data).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "blocks" do
    field :pub_id, :binary_id
    field :state, :string
    field :deleted, :boolean, default: false

    belongs_to :block_type, AttrEngine.Schema.BlockType,
      foreign_key: :block_type_id

    belongs_to :attribute_set_data, AttrEngine.Schema.AttributeSetData,
      foreign_key: :attribute_set_data_id

    timestamps(type: :utc_datetime)
  end

  @cast_fields [:pub_id, :state, :deleted, :block_type_id, :attribute_set_data_id]

  def changeset(block, attrs) do
    block
    |> cast(attrs, @cast_fields)
    |> validate_required([:block_type_id, :attribute_set_data_id])
    |> maybe_put_pub_id()
  end

  defp maybe_put_pub_id(cs) do
    case fetch_field(cs, :pub_id) do
      {:data, nil} -> put_change(cs, :pub_id, Ecto.UUID.generate())
      {:changes, nil} -> put_change(cs, :pub_id, Ecto.UUID.generate())
      _ -> cs
    end
  end
end
