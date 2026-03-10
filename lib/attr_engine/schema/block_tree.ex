defmodule AttrEngine.Schema.BlockTree do
  @moduledoc """
  Parent-child relationships between blocks — polymorphic.

  BlockTree links blocks to parents (pages, other blocks, or any host-app entity).
  The `parent_type` + `parent_id` pair is polymorphic — the host app defines
  what kinds of parents exist.

  ## Examples

  - CMS: `parent_type: "page", parent_id: 42` — block belongs to a page
  - CMS: `parent_type: "block", parent_id: 7` — nested block
  - ArtistCircle: `parent_type: "gallery", parent_id: 3` — piece in a gallery
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "block_trees" do
    field :parent_type, :string
    field :parent_id, :integer
    field :position, :integer, default: 0

    belongs_to :block, AttrEngine.Schema.Block,
      foreign_key: :block_id

    timestamps(type: :utc_datetime)
  end

  @cast_fields [:parent_type, :parent_id, :position, :block_id]

  def changeset(tree, attrs) do
    tree
    |> cast(attrs, @cast_fields)
    |> validate_required([:parent_type, :parent_id, :block_id])
  end
end
