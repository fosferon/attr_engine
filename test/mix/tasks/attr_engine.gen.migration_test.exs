defmodule Mix.Tasks.AttrEngine.Gen.MigrationTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.AttrEngine.Gen.Migration

  describe "migration_content/2 — SQLite branch" do
    setup do
      %{sql: Migration.migration_content("", :sqlite)}
    end

    test "emits no Postgres-only :uuid columns", %{sql: sql} do
      refute sql =~ ":uuid"
      # uuid-typed columns become plain strings (Ecto.UUID round-trips as TEXT)
      assert sql =~ "add :pub_id, :string"
      assert sql =~ "add :owner_id, :string"
      assert sql =~ "add :type_id, :string, primary_key: true"
    end

    test "emits no ALTER TABLE ... ADD CONSTRAINT (SQLite cannot)", %{sql: sql} do
      refute sql =~ "ADD CONSTRAINT"
      refute sql =~ "execute "
    end

    test "still creates every attr_engine table", %{sql: sql} do
      assert sql =~ "use Ecto.Migration"

      for t <- ~w(attributes attribute_sets attribute_set_attributes attribute_set_data
                  block_types blocks block_trees attribute_set_trees
                  attribute_set_type_associations) do
        assert sql =~ "create table(:#{t}", "SQLite migration is missing table #{t}"
      end
    end

    test "generated source compiles as a real Ecto migration module", %{sql: sql} do
      # Proves the hand-written template is valid Elixir + Ecto migration DSL.
      [{mod, _bin}] = Code.compile_string(sql)
      assert function_exported?(mod, :__migration__, 0)
      assert function_exported?(mod, :change, 0)
    after
      :code.purge(AttrEngine.Repo.Migrations.CreateAttrEngineTables)
      :code.delete(AttrEngine.Repo.Migrations.CreateAttrEngineTables)
    end
  end

  describe "migration_content/2 — Postgres branch (unchanged)" do
    test "still uses :uuid columns and the CHECK constraint" do
      pg = Migration.migration_content("", :postgres)
      assert pg =~ "add :pub_id, :uuid"
      assert pg =~ "add :owner_id, :uuid"
      assert pg =~ "ADD CONSTRAINT"
    end

    test "an unknown adapter falls back to the Postgres template" do
      assert Migration.migration_content("", :something_else) ==
               Migration.migration_content("", :postgres)
    end
  end

  describe "prefix application (SQLite branch)" do
    test "prefixes table names" do
      assert Migration.migration_content("cot_", :sqlite) =~
               "create table(:cot_attribute_set_data"
    end
  end

  describe "resolve_adapter/1" do
    test "explicit --db sqlite wins" do
      assert Migration.resolve_adapter(db: "sqlite") == :sqlite
      assert Migration.resolve_adapter(db: "sqlite3") == :sqlite
    end

    test "explicit --db postgres wins" do
      assert Migration.resolve_adapter(db: "postgres") == :postgres
      assert Migration.resolve_adapter(db: "pg") == :postgres
    end

    test "with no --db and no configured repo, defaults to :postgres (no regression)" do
      assert Migration.resolve_adapter([]) == :postgres
    end
  end
end
