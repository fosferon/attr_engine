defmodule AttrEngine.Schema.AttributeSet do
  @moduledoc """
  Named group of attributes — a reusable content shape.

  An AttributeSet groups Attributes via the ASA join table, forming a
  "schema" for a block, piece, entity, or form. It carries its own
  `ui_config` (container-level presentation) and `data_config`.

  ## Composition

  AttributeSets can form DAG hierarchies via `AttrEngine.Schema.AttributeSetTree`:
  - **includes** — composition, child attributes added to parent
  - **extends** — inheritance, child specialises parent
  - **overrides** — explicit override of specific attributes

  ## Typing

  AttributeSets can be classified by Types via `AttrEngine.Schema.AttributeSetTypeAssociation`,
  allowing the same system to distinguish "CMS block", "entity schema", "piece", etc.

  ## Multilingual

  The `translations` field holds JSONB maps for translatable metadata:
    %{"name" => %{"en" => "Hero Banner", "el" => "Κεντρικό Banner"}}
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "attribute_sets" do
    field :pub_id, :binary_id
    field :sid, :integer
    field :name, :string
    field :handle, :string
    field :code, :string
    field :description, :string
    field :state, :string
    field :schema, :string, default: "standalone"

    # Config
    field :ui_config, :map, default: %{}
    field :data_config, :map, default: %{}
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

    # Multilingual metadata
    field :translations, :map, default: %{}

    # Easy mode — virtual
    field :easy_mode, :boolean, virtual: true, default: false

    has_many :attribute_set_attributes, AttrEngine.Schema.AttributeSetAttribute

    many_to_many :attributes, AttrEngine.Schema.Attribute,
      join_through: AttrEngine.Schema.AttributeSetAttribute,
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @cast_fields [
    :pub_id, :sid, :name, :handle, :code, :description, :state, :schema,
    :ui_config, :data_config, :validations,
    :active, :system, :searchable, :exportable, :importable,
    :readonly, :visible, :deleted, :sort, :translations, :easy_mode
  ]

  @doc "Standard changeset with easy_mode support."
  def changeset(attribute_set, attrs, opts \\ []) do
    attribute_set
    |> cast(attrs, @cast_fields)
    |> maybe_put_pub_id()
    |> validate_required([:name])
    |> handle_easy_mode()
    |> maybe_validate_unique_handle(opts)
    |> maybe_lock_handle()
  end

  # --- Easy mode ---

  defp handle_easy_mode(cs) do
    if get_field(cs, :easy_mode) do
      cs
      |> maybe_generate_handle()
      |> maybe_generate_code()
      |> maybe_set_defaults()
    else
      cs |> validate_required([:handle, :state])
    end
  end

  defp maybe_generate_handle(cs) do
    case {get_field(cs, :handle), get_change(cs, :name)} do
      {h, name} when (is_nil(h) or h == "") and is_binary(name) ->
        handle =
          name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9]+/, "_")
          |> String.trim("_")

        put_change(cs, :handle, handle)

      _ ->
        cs
    end
  end

  defp maybe_generate_code(cs) do
    case get_field(cs, :code) do
      c when is_nil(c) or c == "" ->
        put_change(cs, :code, String.upcase(get_field(cs, :handle) || ""))

      _ ->
        cs
    end
  end

  defp maybe_set_defaults(cs) do
    cs
    |> put_change(:state, "initialised")
    |> put_change(:visible, true)
    |> put_change(:searchable, true)
    |> put_change(:exportable, true)
    |> put_change(:importable, true)
  end

  # --- Handle locking ---

  defp maybe_lock_handle(cs) do
    if persisted?(cs) and Map.has_key?(cs.changes, :handle) do
      ui = get_field(cs, :ui_config) || %{}
      lock = Map.get(ui, "lock_handle", Map.get(ui, :lock_handle, true))

      if lock do
        add_error(cs, :handle, "is locked and cannot be changed")
      else
        cs
      end
    else
      cs
    end
  end

  # --- Unique handle validation (requires repo) ---

  defp maybe_validate_unique_handle(cs, opts) do
    tenant_id = Keyword.get(opts, :tenant_id)

    if tenant_id && get_change(cs, :handle) do
      validate_change(cs, :handle, fn :handle, handle ->
        import Ecto.Query

        query =
          from(as in __MODULE__,
            where: as.handle == ^handle,
            select: count(as.id)
          )

        query =
          case get_field(cs, :id) do
            nil -> query
            id -> from(as in query, where: as.id != ^id)
          end

        case AttrEngine.repo().one(query) do
          0 -> []
          _ -> [handle: "has already been taken"]
        end
      end)
    else
      cs
    end
  end

  defp persisted?(cs), do: get_field(cs, :id) != nil

  defp maybe_put_pub_id(cs) do
    case fetch_field(cs, :pub_id) do
      {:data, nil} -> put_change(cs, :pub_id, Ecto.UUID.generate())
      {:changes, nil} -> put_change(cs, :pub_id, Ecto.UUID.generate())
      _ -> cs
    end
  end
end
