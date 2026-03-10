defmodule AttrEngine.Schema.BlockType do
  @moduledoc """
  Defines a renderable block shape: handle + template + AttributeSet.

  A BlockType binds an AttributeSet (the data shape) to a template
  (the rendering instructions). The template can be a Mustache string,
  a component reference, or nil for programmatic rendering.

  ## Examples

  - CMS: `heading_block` → AttributeSet with title/subtitle/intro + Mustache template
  - ArtistCircle: `piece` → AttributeSet with work/legend/audio + JS animation envelope
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "block_types" do
    field :pub_id, :binary_id
    field :handle, :string
    field :name, :string
    field :description, :string
    field :state, :string

    # Template — Mustache markup, or nil for component-rendered blocks
    field :template, :string

    # Block-level config — e.g. pipe transforms, data requirements
    field :data_config, :map, default: %{}

    field :deleted, :boolean, default: false

    belongs_to :attribute_set, AttrEngine.Schema.AttributeSet,
      foreign_key: :attribute_set_id

    timestamps(type: :utc_datetime)
  end

  @cast_fields [
    :pub_id, :handle, :name, :description, :state,
    :template, :data_config, :deleted, :attribute_set_id
  ]

  def changeset(block_type, attrs) do
    block_type
    |> cast(attrs, @cast_fields)
    |> validate_required([:handle, :name])
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
