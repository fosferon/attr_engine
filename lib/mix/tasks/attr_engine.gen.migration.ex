defmodule Mix.Tasks.AttrEngine.Gen.Migration do
  @moduledoc """
  Generates Ecto migrations for AttrEngine tables.

  ## Usage

      mix attr_engine.gen.migration

  ## Options

      --prefix PREFIX   Table name prefix (e.g. "cms_" or "ac_")
      --repo REPO       Target Ecto repo module

  Creates migrations for:
  - attributes
  - attribute_sets
  - attribute_set_attributes (join table)
  - attribute_set_data
  - block_types
  - blocks
  - block_trees
  - attribute_set_trees (DAG)
  - attribute_set_type_associations
  """

  use Mix.Task

  @shortdoc "Generates AttrEngine database migrations"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [prefix: :string, repo: :string, db: :string])

    prefix = opts[:prefix] || ""
    adapter = resolve_adapter(opts)

    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")

    migration_content = migration_content(prefix, adapter)

    # Determine migrations path
    migrations_path = Path.join(["priv", "repo", "migrations"])

    File.mkdir_p!(migrations_path)
    filename = "#{timestamp}_create_attr_engine_tables.exs"
    filepath = Path.join(migrations_path, filename)

    File.write!(filepath, migration_content)
    Mix.shell().info([:green, "* creating ", :reset, filepath, " (#{adapter})"])
  end

  @doc """
  Renders the migration source for the given `prefix` and `adapter`.

  `adapter` is `:postgres` (the default, unchanged) or `:sqlite`. Exposed for
  testing the adapter branch without touching the filesystem.
  """
  @spec migration_content(String.t(), :postgres | :sqlite) :: String.t()
  def migration_content(prefix, :sqlite), do: sqlite_migration_template(prefix)
  def migration_content(prefix, _postgres), do: migration_template(prefix)

  @doc """
  Resolves the target adapter from CLI opts, then the configured repo.

  Precedence: an explicit `--db sqlite|postgres` flag wins; otherwise the
  configured repo's `__adapter__/0` decides (that's "the type of db in the
  config" branching out). Anything unresolved falls back to `:postgres`, so
  existing Postgres consumers are never affected.
  """
  @spec resolve_adapter(keyword()) :: :postgres | :sqlite
  def resolve_adapter(opts) do
    case normalize_db(opts[:db]) do
      :sqlite -> :sqlite
      :postgres -> :postgres
      nil -> adapter_from_repo(opts[:repo])
    end
  end

  defp normalize_db(nil), do: nil

  defp normalize_db(db) do
    case String.downcase(to_string(db)) do
      d when d in ["sqlite", "sqlite3", "ecto_sqlite3"] -> :sqlite
      d when d in ["postgres", "postgresql", "pg", "postgrex"] -> :postgres
      _ -> nil
    end
  end

  defp adapter_from_repo(repo_arg) do
    # Load the host app's config so `config :attr_engine, repo: ...` is visible.
    _ = Mix.Task.run("app.config", [])

    repo =
      case repo_arg do
        r when is_binary(r) -> Module.concat([r])
        _ -> Application.get_env(:attr_engine, :repo)
      end

    case repo && repo.__adapter__() do
      Ecto.Adapters.SQLite3 -> :sqlite
      _ -> :postgres
    end
  rescue
    _ -> :postgres
  end

  defp migration_template(prefix) do
    p = fn name -> "#{prefix}#{name}" end

    """
    defmodule AttrEngine.Repo.Migrations.CreateAttrEngineTables do
      use Ecto.Migration

      def change do
        # --- Attributes ---
        create table(:#{p.("attributes")}) do
          add :pub_id, :uuid
          add :name, :string, null: false
          add :handle, :string, null: false
          add :code, :string
          add :description, :text
          add :state, :string, default: "initialised"

          add :data_config, :map, default: %{}
          add :ui_config, :map, default: %{}
          add :validations, :map, default: %{}

          add :active, :boolean, default: false
          add :system, :boolean, default: false
          add :searchable, :boolean, default: false
          add :exportable, :boolean, default: false
          add :importable, :boolean, default: false
          add :readonly, :boolean, default: false
          add :visible, :boolean, default: false
          add :deleted, :boolean, default: false

          add :sort, :integer, default: 0
          add :translations, :map, default: %{}

          timestamps(type: :utc_datetime)
        end

        create unique_index(:#{p.("attributes")}, [:handle])
        create index(:#{p.("attributes")}, [:pub_id])
        create index(:#{p.("attributes")}, [:state])

        # --- Attribute Sets ---
        create table(:#{p.("attribute_sets")}) do
          add :pub_id, :uuid
          add :sid, :integer
          add :name, :string, null: false
          add :handle, :string, null: false
          add :code, :string
          add :description, :text
          add :state, :string, default: "initialised"
          add :schema, :string, default: "standalone"

          add :ui_config, :map, default: %{}
          add :data_config, :map, default: %{}
          add :validations, :map, default: %{}

          add :active, :boolean, default: false
          add :system, :boolean, default: false
          add :searchable, :boolean, default: false
          add :exportable, :boolean, default: false
          add :importable, :boolean, default: false
          add :readonly, :boolean, default: false
          add :visible, :boolean, default: false
          add :deleted, :boolean, default: false

          add :sort, :integer, default: 0
          add :translations, :map, default: %{}

          timestamps(type: :utc_datetime)
        end

        create unique_index(:#{p.("attribute_sets")}, [:handle])
        create index(:#{p.("attribute_sets")}, [:pub_id])
        create index(:#{p.("attribute_sets")}, [:state])

        # --- Attribute Set Attributes (join table with surrogate PK) ---
        create table(:#{p.("attribute_set_attributes")}) do
          add :attribute_set_id, references(:#{p.("attribute_sets")}, on_delete: :delete_all), null: false
          add :attribute_id, references(:#{p.("attributes")}, on_delete: :delete_all), null: false

          add :name, :string
          add :handle, :string, null: false
          add :code, :string
          add :description, :text
          add :state, :string

          add :data_config, :map, default: %{}
          add :ui_config, :map, default: %{}
          add :validations, :map, default: %{}

          add :active, :boolean, default: false
          add :system, :boolean, default: false
          add :searchable, :boolean, default: false
          add :exportable, :boolean, default: false
          add :importable, :boolean, default: false
          add :readonly, :boolean, default: false
          add :visible, :boolean, default: false
          add :deleted, :boolean, default: false

          add :sort, :integer, default: 0
          add :translations, :map, default: %{}

          timestamps(type: :utc_datetime)
        end

        create unique_index(:#{p.("attribute_set_attributes")}, [:attribute_set_id, :handle],
          name: :#{p.("attribute_set_attributes")}_unique_set_handle
        )
        create index(:#{p.("attribute_set_attributes")}, [:attribute_set_id])
        create index(:#{p.("attribute_set_attributes")}, [:attribute_id])

        execute "ALTER TABLE #{p.("attribute_set_attributes")} ADD CONSTRAINT #{p.("asa_handle_non_empty")} CHECK (handle <> '')"

        # --- Attribute Set Data ---
        create table(:#{p.("attribute_set_data")}) do
          add :pub_id, :uuid
          add :sid, :integer
          add :data, :map, default: %{}, null: false
          add :ui_config, :map, default: %{}
          add :state, :string
          add :deleted, :boolean, default: false

          add :owner_id, :uuid
          add :owner_type, :string

          add :attribute_set_id, references(:#{p.("attribute_sets")}, on_delete: :restrict), null: false

          timestamps(type: :utc_datetime)
        end

        create index(:#{p.("attribute_set_data")}, [:pub_id])
        create index(:#{p.("attribute_set_data")}, [:attribute_set_id])
        create index(:#{p.("attribute_set_data")}, [:owner_id, :owner_type])

        # --- Block Types ---
        create table(:#{p.("block_types")}) do
          add :pub_id, :uuid
          add :handle, :string, null: false
          add :name, :string, null: false
          add :description, :text
          add :state, :string
          add :template, :text
          add :data_config, :map, default: %{}
          add :deleted, :boolean, default: false

          add :attribute_set_id, references(:#{p.("attribute_sets")}, on_delete: :restrict)

          timestamps(type: :utc_datetime)
        end

        create unique_index(:#{p.("block_types")}, [:handle])

        # --- Blocks ---
        create table(:#{p.("blocks")}) do
          add :pub_id, :uuid
          add :state, :string
          add :deleted, :boolean, default: false

          add :block_type_id, references(:#{p.("block_types")}, on_delete: :restrict), null: false
          add :attribute_set_data_id, references(:#{p.("attribute_set_data")}, on_delete: :restrict), null: false

          timestamps(type: :utc_datetime)
        end

        create index(:#{p.("blocks")}, [:block_type_id])
        create index(:#{p.("blocks")}, [:attribute_set_data_id])

        # --- Block Trees ---
        create table(:#{p.("block_trees")}) do
          add :parent_type, :string, null: false
          add :parent_id, :integer, null: false
          add :position, :integer, default: 0

          add :block_id, references(:#{p.("blocks")}, on_delete: :delete_all), null: false

          timestamps(type: :utc_datetime)
        end

        create index(:#{p.("block_trees")}, [:parent_type, :parent_id])
        create index(:#{p.("block_trees")}, [:block_id])

        # --- Attribute Set Trees (DAG) ---
        create table(:#{p.("attribute_set_trees")}, primary_key: false) do
          add :ancestor, references(:#{p.("attribute_sets")}, on_delete: :delete_all), primary_key: true
          add :descendant, references(:#{p.("attribute_sets")}, on_delete: :delete_all), primary_key: true

          add :depth, :integer, default: 0
          add :order, :integer, default: 0
          add :composition_type, :string, default: "includes"
          add :inheritance, :boolean, default: true
          add :merge_strategy, :string, default: "parent_wins"
          add :override_config, :map

          timestamps(type: :utc_datetime)
        end

        create index(:#{p.("attribute_set_trees")}, [:ancestor])
        create index(:#{p.("attribute_set_trees")}, [:descendant])

        # --- Attribute Set Type Associations ---
        create table(:#{p.("attribute_set_type_associations")}, primary_key: false) do
          add :attribute_set_id, references(:#{p.("attribute_sets")}, on_delete: :delete_all), primary_key: true
          add :type_id, :uuid, primary_key: true

          add :primary, :boolean, default: false

          timestamps(type: :utc_datetime)
        end

        create index(:#{p.("attribute_set_type_associations")}, [:attribute_set_id])
        create index(:#{p.("attribute_set_type_associations")}, [:type_id])
      end
    end
    """
  end

  # SQLite variant of migration_template/1. Identical schema; two adapter deltas:
  #   1. `:uuid` columns -> `:string` (SQLite has no native uuid; matches the
  #      `:binary_id` schema fields under ecto_sqlite3 binary_id_type:string,
  #      so Ecto.UUID values round-trip as TEXT).
  #   2. no `ALTER TABLE ... ADD CONSTRAINT ... CHECK` (SQLite cannot ALTER-ADD
  #      a constraint; app-level validate_handle_non_empty/1 already enforces it).
  # Everything else (:map -> TEXT, integer PKs, indexes, references) is
  # adapter-agnostic and byte-identical to the Postgres template.
  defp sqlite_migration_template(prefix) do
    p = fn name -> "#{prefix}#{name}" end

    """
    defmodule AttrEngine.Repo.Migrations.CreateAttrEngineTables do
      use Ecto.Migration

      def change do
        # --- Attributes ---
        create table(:#{p.("attributes")}) do
          add :pub_id, :string
          add :name, :string, null: false
          add :handle, :string, null: false
          add :code, :string
          add :description, :text
          add :state, :string, default: "initialised"

          add :data_config, :map, default: %{}
          add :ui_config, :map, default: %{}
          add :validations, :map, default: %{}

          add :active, :boolean, default: false
          add :system, :boolean, default: false
          add :searchable, :boolean, default: false
          add :exportable, :boolean, default: false
          add :importable, :boolean, default: false
          add :readonly, :boolean, default: false
          add :visible, :boolean, default: false
          add :deleted, :boolean, default: false

          add :sort, :integer, default: 0
          add :translations, :map, default: %{}

          timestamps(type: :utc_datetime)
        end

        create unique_index(:#{p.("attributes")}, [:handle])
        create index(:#{p.("attributes")}, [:pub_id])
        create index(:#{p.("attributes")}, [:state])

        # --- Attribute Sets ---
        create table(:#{p.("attribute_sets")}) do
          add :pub_id, :string
          add :sid, :integer
          add :name, :string, null: false
          add :handle, :string, null: false
          add :code, :string
          add :description, :text
          add :state, :string, default: "initialised"
          add :schema, :string, default: "standalone"

          add :ui_config, :map, default: %{}
          add :data_config, :map, default: %{}
          add :validations, :map, default: %{}

          add :active, :boolean, default: false
          add :system, :boolean, default: false
          add :searchable, :boolean, default: false
          add :exportable, :boolean, default: false
          add :importable, :boolean, default: false
          add :readonly, :boolean, default: false
          add :visible, :boolean, default: false
          add :deleted, :boolean, default: false

          add :sort, :integer, default: 0
          add :translations, :map, default: %{}

          timestamps(type: :utc_datetime)
        end

        create unique_index(:#{p.("attribute_sets")}, [:handle])
        create index(:#{p.("attribute_sets")}, [:pub_id])
        create index(:#{p.("attribute_sets")}, [:state])

        # --- Attribute Set Attributes (join table with surrogate PK) ---
        create table(:#{p.("attribute_set_attributes")}) do
          add :attribute_set_id, references(:#{p.("attribute_sets")}, on_delete: :delete_all), null: false
          add :attribute_id, references(:#{p.("attributes")}, on_delete: :delete_all), null: false

          add :name, :string
          add :handle, :string, null: false
          add :code, :string
          add :description, :text
          add :state, :string

          add :data_config, :map, default: %{}
          add :ui_config, :map, default: %{}
          add :validations, :map, default: %{}

          add :active, :boolean, default: false
          add :system, :boolean, default: false
          add :searchable, :boolean, default: false
          add :exportable, :boolean, default: false
          add :importable, :boolean, default: false
          add :readonly, :boolean, default: false
          add :visible, :boolean, default: false
          add :deleted, :boolean, default: false

          add :sort, :integer, default: 0
          add :translations, :map, default: %{}

          timestamps(type: :utc_datetime)
        end

        create unique_index(:#{p.("attribute_set_attributes")}, [:attribute_set_id, :handle],
          name: :#{p.("attribute_set_attributes")}_unique_set_handle
        )
        create index(:#{p.("attribute_set_attributes")}, [:attribute_set_id])
        create index(:#{p.("attribute_set_attributes")}, [:attribute_id])

        # --- Attribute Set Data ---
        create table(:#{p.("attribute_set_data")}) do
          add :pub_id, :string
          add :sid, :integer
          add :data, :map, default: %{}, null: false
          add :ui_config, :map, default: %{}
          add :state, :string
          add :deleted, :boolean, default: false

          add :owner_id, :string
          add :owner_type, :string

          add :attribute_set_id, references(:#{p.("attribute_sets")}, on_delete: :restrict), null: false

          timestamps(type: :utc_datetime)
        end

        create index(:#{p.("attribute_set_data")}, [:pub_id])
        create index(:#{p.("attribute_set_data")}, [:attribute_set_id])
        create index(:#{p.("attribute_set_data")}, [:owner_id, :owner_type])

        # --- Block Types ---
        create table(:#{p.("block_types")}) do
          add :pub_id, :string
          add :handle, :string, null: false
          add :name, :string, null: false
          add :description, :text
          add :state, :string
          add :template, :text
          add :data_config, :map, default: %{}
          add :deleted, :boolean, default: false

          add :attribute_set_id, references(:#{p.("attribute_sets")}, on_delete: :restrict)

          timestamps(type: :utc_datetime)
        end

        create unique_index(:#{p.("block_types")}, [:handle])

        # --- Blocks ---
        create table(:#{p.("blocks")}) do
          add :pub_id, :string
          add :state, :string
          add :deleted, :boolean, default: false

          add :block_type_id, references(:#{p.("block_types")}, on_delete: :restrict), null: false
          add :attribute_set_data_id, references(:#{p.("attribute_set_data")}, on_delete: :restrict), null: false

          timestamps(type: :utc_datetime)
        end

        create index(:#{p.("blocks")}, [:block_type_id])
        create index(:#{p.("blocks")}, [:attribute_set_data_id])

        # --- Block Trees ---
        create table(:#{p.("block_trees")}) do
          add :parent_type, :string, null: false
          add :parent_id, :integer, null: false
          add :position, :integer, default: 0

          add :block_id, references(:#{p.("blocks")}, on_delete: :delete_all), null: false

          timestamps(type: :utc_datetime)
        end

        create index(:#{p.("block_trees")}, [:parent_type, :parent_id])
        create index(:#{p.("block_trees")}, [:block_id])

        # --- Attribute Set Trees (DAG) ---
        create table(:#{p.("attribute_set_trees")}, primary_key: false) do
          add :ancestor, references(:#{p.("attribute_sets")}, on_delete: :delete_all), primary_key: true
          add :descendant, references(:#{p.("attribute_sets")}, on_delete: :delete_all), primary_key: true

          add :depth, :integer, default: 0
          add :order, :integer, default: 0
          add :composition_type, :string, default: "includes"
          add :inheritance, :boolean, default: true
          add :merge_strategy, :string, default: "parent_wins"
          add :override_config, :map

          timestamps(type: :utc_datetime)
        end

        create index(:#{p.("attribute_set_trees")}, [:ancestor])
        create index(:#{p.("attribute_set_trees")}, [:descendant])

        # --- Attribute Set Type Associations ---
        create table(:#{p.("attribute_set_type_associations")}, primary_key: false) do
          add :attribute_set_id, references(:#{p.("attribute_sets")}, on_delete: :delete_all), primary_key: true
          add :type_id, :string, primary_key: true

          add :primary, :boolean, default: false

          timestamps(type: :utc_datetime)
        end

        create index(:#{p.("attribute_set_type_associations")}, [:attribute_set_id])
        create index(:#{p.("attribute_set_type_associations")}, [:type_id])
      end
    end
    """
  end
end
