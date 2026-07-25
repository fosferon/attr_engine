defmodule AttrEngine.RelationTest do
  use ExUnit.Case, async: false

  alias AttrEngine.Relation
  alias AttrEngine.Test.InMemoryAdapter

  setup do
    InMemoryAdapter.start_link(%{"existing_ref" => "resolved_value"})
    Application.put_env(:attr_engine, :relation_sources, %{"memory" => InMemoryAdapter})

    on_exit(fn ->
      InMemoryAdapter.stop()
      Application.delete_env(:attr_engine, :relation_sources)
    end)
  end

  defp relation_meta(handle, opts \\ %{}) do
    rc = Map.merge(%{"source" => "memory"}, opts)

    %{
      handle: handle,
      type: :relation,
      data_config: %{"type" => "relation", "relation_config" => rc}
    }
  end

  describe "resolve_relations/3 — read path" do
    test "resolves a ref to its target value" do
      attrs_meta = [relation_meta("credential")]
      data = %{"credential" => "existing_ref"}

      assert {:ok, resolved} = Relation.resolve_relations(attrs_meta, data)
      assert resolved["credential"] == "resolved_value"
    end

    test "skips ref_only relations by default" do
      attrs_meta = [relation_meta("credential", %{"ref_only" => true})]
      data = %{"credential" => "existing_ref"}

      assert {:ok, resolved} = Relation.resolve_relations(attrs_meta, data)
      assert resolved["credential"] == "existing_ref"
    end

    test "resolves ref_only when skip_ref_only: false" do
      attrs_meta = [relation_meta("credential", %{"ref_only" => true})]
      data = %{"credential" => "existing_ref"}

      assert {:ok, resolved} = Relation.resolve_relations(attrs_meta, data, skip_ref_only: false)
      assert resolved["credential"] == "resolved_value"
    end

    test "returns error for missing adapter" do
      attrs_meta = [relation_meta("credential", %{"source" => "nonexistent"})]
      data = %{"credential" => "some_ref"}

      assert {:error, errors} = Relation.resolve_relations(attrs_meta, data)
      assert {"credential", :no_adapter} in errors
    end

    test "returns error when ref not found in target" do
      attrs_meta = [relation_meta("credential")]
      data = %{"credential" => "missing_ref"}

      assert {:error, errors} = Relation.resolve_relations(attrs_meta, data)
      assert {"credential", :not_found} in errors
    end

    test "skips nil refs without error" do
      attrs_meta = [relation_meta("credential")]
      data = %{"credential" => nil}

      assert {:ok, resolved} = Relation.resolve_relations(attrs_meta, data)
      assert resolved["credential"] == nil
    end

    test "leaves non-relation attributes untouched" do
      attrs_meta = [
        %{handle: "name", type: :string, data_config: %{"type" => "binary"}},
        relation_meta("credential")
      ]

      data = %{"name" => "My App", "credential" => "existing_ref"}

      assert {:ok, resolved} = Relation.resolve_relations(attrs_meta, data)
      assert resolved["name"] == "My App"
      assert resolved["credential"] == "resolved_value"
    end
  end

  describe "process_writes/2 — write path" do
    test "routes value to adapter and replaces with ref" do
      attrs_meta = [relation_meta("credential", %{"ref_only" => true, "ref_key" => "my_cred"})]
      incoming = %{"credential" => "raw_sensitive_data"}

      assert {:ok, processed} = Relation.process_writes(attrs_meta, incoming)
      assert processed["credential"] == "my_cred"

      # Value is in the target store
      assert InMemoryAdapter.get_all() == %{
               "existing_ref" => "resolved_value",
               "my_cred" => "raw_sensitive_data"
             }
    end

    test "skips nil values on write" do
      attrs_meta = [relation_meta("credential", %{"ref_only" => true})]
      incoming = %{"credential" => nil}

      assert {:ok, processed} = Relation.process_writes(attrs_meta, incoming)
      assert processed["credential"] == nil
    end

    test "only processes ref_only relations" do
      attrs_meta = [relation_meta("linked_record", %{"ref_only" => false})]
      incoming = %{"linked_record" => "some_value"}

      assert {:ok, processed} = Relation.process_writes(attrs_meta, incoming)
      # Value passes through unchanged (not routed to adapter)
      assert processed["linked_record"] == "some_value"
    end

    test "returns error for missing adapter on write" do
      attrs_meta = [relation_meta("credential", %{"source" => "nonexistent", "ref_only" => true})]
      incoming = %{"credential" => "some_value"}

      assert {:error, errors} = Relation.process_writes(attrs_meta, incoming)
      assert {"credential", :no_adapter} in errors
    end

    test "raw value never remains in ASD output for ref_only" do
      attrs_meta = [relation_meta("token", %{"ref_only" => true, "ref_key" => "token_ref"})]
      raw_value = "super_sensitive_token_value"
      incoming = %{"token" => raw_value}

      assert {:ok, processed} = Relation.process_writes(attrs_meta, incoming)
      refute processed["token"] == raw_value
      assert processed["token"] == "token_ref"
    end
  end

  describe "cleanup/2" do
    test "deletes target values for all relation refs" do
      attrs_meta = [relation_meta("credential")]
      data = %{"credential" => "existing_ref"}

      assert :ok = Relation.cleanup(attrs_meta, data)
      assert InMemoryAdapter.get_all() == %{}
    end

    test "skips nil refs" do
      attrs_meta = [relation_meta("credential")]
      data = %{"credential" => nil}

      assert :ok = Relation.cleanup(attrs_meta, data)
      assert InMemoryAdapter.get_all() == %{"existing_ref" => "resolved_value"}
    end
  end

  describe "lookup_adapter/1" do
    test "returns registered adapter module" do
      assert Relation.lookup_adapter(%{"source" => "memory"}) == InMemoryAdapter
    end

    test "returns nil for unknown source" do
      assert Relation.lookup_adapter(%{"source" => "unknown"}) == nil
    end

    test "returns nil when no source key" do
      assert Relation.lookup_adapter(%{}) == nil
    end
  end

  describe "composition with transforms" do
    test "ref_only relation + redact_secret transform masks the ref" do
      attrs_meta = [
        %{
          handle: "credential",
          type: :relation,
          data_config: %{
            "type" => "relation",
            "transform" => "redact_secret",
            "relation_config" => %{"source" => "memory", "ref_only" => true}
          }
        }
      ]

      data = %{"credential" => "existing_ref"}

      # resolve_relations skips ref_only by default (ref stays)
      {:ok, after_resolve} = Relation.resolve_relations(attrs_meta, data)
      assert after_resolve["credential"] == "existing_ref"

      # Transform masks the ref for rendered output
      transformed = AttrEngine.Transform.apply_transforms(attrs_meta, after_resolve)
      assert transformed["credential"] == "[provided]"
    end

    test "nil ref + redact_secret shows not set" do
      attrs_meta = [
        %{
          handle: "credential",
          type: :relation,
          data_config: %{
            "type" => "relation",
            "transform" => "redact_secret",
            "relation_config" => %{"source" => "memory", "ref_only" => true}
          }
        }
      ]

      data = %{"credential" => nil}

      {:ok, after_resolve} = Relation.resolve_relations(attrs_meta, data)
      transformed = AttrEngine.Transform.apply_transforms(attrs_meta, after_resolve)
      assert transformed["credential"] == "[not set]"
    end
  end

  describe "full round-trip" do
    test "write stores value, read resolves ref, render masks it" do
      attrs_meta = [
        %{
          handle: "token",
          type: :relation,
          data_config: %{
            "type" => "relation",
            "transform" => "redact_secret",
            "relation_config" => %{
              "source" => "memory",
              "ref_only" => true,
              "ref_key" => "token_ref"
            }
          }
        }
      ]

      raw_value = "the_actual_token_value"
      incoming = %{"token" => raw_value}

      # WRITE: value routed to store, ref returned
      {:ok, asd_data} = Relation.process_writes(attrs_meta, incoming)
      assert asd_data["token"] == "token_ref"
      refute asd_data["token"] == raw_value

      # READ (backend, authorized): resolve ref to value
      {:ok, resolved} = Relation.resolve_relations(attrs_meta, asd_data, skip_ref_only: false)
      assert resolved["token"] == raw_value

      # RENDER (frontend, exposed): ref masked by transform
      {:ok, for_render} = Relation.resolve_relations(attrs_meta, asd_data)
      rendered = AttrEngine.Transform.apply_transforms(attrs_meta, for_render)
      assert rendered["token"] == "[provided]"
      refute rendered["token"] == raw_value
    end
  end
end
