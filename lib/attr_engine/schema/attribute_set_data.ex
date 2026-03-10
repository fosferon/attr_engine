defmodule AttrEngine.Schema.AttributeSetData do
  @moduledoc """
  Content instance — the actual JSONB data for an AttributeSet.

  ASD holds the values that fill the shape defined by an AttributeSet.
  Each ASD is a row of content: a CMS block's data, an artist's piece,
  an entity's custom attributes.

  ## Data shape

  The `data` field is a JSONB map keyed by attribute handles:

      %{
        "title" => %{"en" => "Welcome", "el" => "Καλωσήρθατε"},
        "image" => %{"url" => "/assets/abc123", "alt" => "..."},
        "featured" => true
      }

  Localized fields nest by locale key. Non-localized fields are flat values.

  ## Config cascade — Layer 3

  `ui_config` on ASD provides per-instance presentation overrides:

      %{
        "title" => %{"classes" => "text-center", "append" => true}
      }

  These are applied on top of the ASA's ui_config.

  ## Ownership

  `owner_id` and `owner_type` support multi-tenant ownership — "who created this".
  The host app decides what these reference (user, account, artist, etc.).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "attribute_set_data" do
    field :pub_id, :binary_id
    field :sid, :integer
    field :data, :map, default: %{}
    field :ui_config, :map, default: %{}
    field :state, :string
    field :deleted, :boolean, default: false

    # Ownership — polymorphic, host app defines what these reference
    field :owner_id, :binary_id
    field :owner_type, :string

    belongs_to :attribute_set, AttrEngine.Schema.AttributeSet,
      foreign_key: :attribute_set_id

    timestamps(type: :utc_datetime)
  end

  @cast_fields [
    :pub_id, :sid, :data, :ui_config, :state, :deleted,
    :owner_id, :owner_type, :attribute_set_id
  ]

  @doc "Standard changeset — requires data and attribute_set_id."
  def changeset(asd, attrs) do
    asd
    |> cast(attrs, @cast_fields)
    |> validate_required([:data, :attribute_set_id])
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
