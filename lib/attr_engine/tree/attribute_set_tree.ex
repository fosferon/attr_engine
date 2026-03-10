defmodule AttrEngine.Tree.AttributeSetTree do
  @moduledoc """
  Closure table for AttributeSet DAG hierarchies.

  Enables composition and inheritance between attribute sets:

  - **includes** — composition: child attributes are added to parent
  - **extends** — inheritance: child specialises parent
  - **overrides** — explicit override of specific attributes

  ## Merge strategies

  When attribute sets compose, handle collisions are resolved by:
  - `parent_wins` — parent's config takes precedence
  - `child_wins` — child's config takes precedence
  - `merge` — deep merge of configs

  ## Override config

  Allows fine-grained override of individual attribute handles:

      %{"email" => %{"required" => true}, "phone" => %{"visible" => false}}
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :id

  schema "attribute_set_trees" do
    field :depth, :integer, default: 0
    field :order, :integer, default: 0

    # Relationship type
    field :composition_type, :string, default: "includes"

    # Whether child inherits parent configs
    field :inheritance, :boolean, default: true

    # Conflict resolution
    field :merge_strategy, :string, default: "parent_wins"

    # Per-handle override map
    field :override_config, :map

    belongs_to :parent, AttrEngine.Schema.AttributeSet,
      foreign_key: :ancestor,
      primary_key: true

    belongs_to :child, AttrEngine.Schema.AttributeSet,
      foreign_key: :descendant,
      primary_key: true

    timestamps(type: :utc_datetime)
  end

  @cast_fields [
    :ancestor, :descendant, :depth, :order,
    :composition_type, :inheritance, :merge_strategy, :override_config
  ]

  def changeset(tree, attrs) do
    tree
    |> cast(attrs, @cast_fields)
    |> validate_required([:ancestor, :descendant])
    |> validate_inclusion(:composition_type, ["includes", "extends", "overrides"])
    |> validate_inclusion(:merge_strategy, ["parent_wins", "child_wins", "merge"])
  end
end
