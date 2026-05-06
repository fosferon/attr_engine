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
        :sort
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

  schema "attribute_sets" do
    field :pub_id, :binary_id
    field :sid, :integer
    field :name, :string
    field :handle, :string
    field :code, :string
    field :description, :string
    field :state, :string
    field :schema, :string, default: "Standalone"

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

  # --- Field lists for easy_mode vs full mode ---

  @base_fields_easy [
    :pub_id, :name, :description, :active,
    :ui_config, :data_config, :validations, :translations
  ]

  @base_fields_full [
    :pub_id, :name, :handle, :code, :description, :state, :sort,
    :active, :visible, :readonly, :deleted, :system,
    :searchable, :exportable, :importable,
    :ui_config, :data_config, :validations, :translations
  ]

  @required_easy [:name, :active]

  @required_full [
    :name, :handle, :code, :state, :active, :visible, :system,
    :searchable, :exportable, :importable, :readonly, :deleted, :sort
  ]

  @doc """
  Standard changeset with easy_mode support.

  In easy_mode, handle, code, state, and flags are auto-generated from the
  name. In full mode, all fields must be provided explicitly.

  ## Options

  - `:tenant_id` — when set, validates handle uniqueness within the tenant
  """
  @spec changeset(%__MODULE__{}, map(), keyword()) :: Ecto.Changeset.t()
  def changeset(attribute_set, attrs, opts \\ []) do
    easy_mode = get_in(attrs, ["easy_mode"]) || false

    attribute_set
    |> cast(attrs, base_fields(easy_mode))
    |> maybe_put_pub_id()
    |> maybe_generate_handle(easy_mode)
    |> maybe_generate_code(easy_mode)
    |> maybe_set_defaults(easy_mode)
    |> validate_required(required_fields(easy_mode))
    |> maybe_validate_unique_handle(opts)
    |> maybe_lock_handle()
    |> handle_attributes()
  end

  @doc """
  Setup changeset for workflow-driven creation with nested attributes.

  Like `changeset/3` but uses `cast_assoc(:attributes)` to create nested
  Attribute records in a single operation. Used by attribute set creation
  workflows that define the set and its attributes in one step.

  ## Options

  - `:tenant_id` — when set, validates handle uniqueness within the tenant
  """
  @spec setup_changeset(%__MODULE__{}, map(), keyword()) :: Ecto.Changeset.t()
  def setup_changeset(attribute_set, attrs, opts \\ []) do
    easy_mode = get_in(attrs, ["easy_mode"]) || false

    attribute_set
    |> cast(attrs, base_fields(easy_mode))
    |> maybe_put_pub_id()
    |> maybe_generate_handle(easy_mode)
    |> maybe_generate_code(easy_mode)
    |> maybe_set_defaults(easy_mode)
    |> validate_required(required_fields(easy_mode))
    |> maybe_validate_unique_handle(opts)
    |> maybe_lock_handle()
    |> cast_assoc(:attributes, with: &AttrEngine.Schema.Attribute.changeset/2)
  end

  # --- Field lists ---

  defp base_fields(true), do: @base_fields_easy
  defp base_fields(_), do: @base_fields_full

  defp required_fields(true), do: @required_easy
  defp required_fields(_), do: @required_full

  # --- Easy mode auto-generation ---

  defp maybe_generate_handle(changeset, true) do
    case get_change(changeset, :name) do
      nil ->
        changeset

      name ->
        handle =
          name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9]+/, "_")
          |> String.trim("_")

        put_change(changeset, :handle, handle)
    end
  end

  defp maybe_generate_handle(changeset, _), do: changeset

  defp maybe_generate_code(changeset, true) do
    case get_field(changeset, :handle) do
      nil -> changeset
      handle -> put_change(changeset, :code, String.upcase(handle))
    end
  end

  defp maybe_generate_code(changeset, _), do: changeset

  defp maybe_set_defaults(changeset, true) do
    changeset
    |> put_change(:state, "initialised")
    |> put_change(:visible, true)
    |> put_change(:system, false)
    |> put_change(:searchable, true)
    |> put_change(:exportable, true)
    |> put_change(:importable, true)
    |> put_change(:readonly, false)
    |> put_change(:deleted, false)
    |> put_change(:sort, 0)
  end

  defp maybe_set_defaults(changeset, _), do: changeset

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

  # --- Attribute association handling ---

  defp handle_attributes(changeset) do
    case get_field(changeset, :state) do
      "initialised" ->
        cast_assoc(changeset, :attributes)

      _ ->
        cast_assoc(changeset, :attributes, required: true)
    end
  end

  # --- Unique handle validation ---

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

  # --- Helpers ---

  defp persisted?(cs), do: get_field(cs, :id) != nil

  defp maybe_put_pub_id(cs) do
    case fetch_field(cs, :pub_id) do
      {:data, nil} -> put_change(cs, :pub_id, Ecto.UUID.generate())
      {:changes, nil} -> put_change(cs, :pub_id, Ecto.UUID.generate())
      _ -> cs
    end
  end
end
