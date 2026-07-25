defmodule AttrEngine.TransformTest do
  use ExUnit.Case, async: true

  alias AttrEngine.Transform

  describe "resolve/2 — single named transform" do
    test "applies a built-in transform by name" do
      dc = %{"transform" => "redact"}
      assert Transform.resolve("secret_key_123", dc) == "••••••••"
    end

    test "returns value unchanged when no transform declared" do
      dc = %{"type" => "binary"}
      assert Transform.resolve("hello", dc) == "hello"
    end

    test "returns value unchanged for unknown transform name" do
      dc = %{"transform" => "nonexistent"}
      assert Transform.resolve("hello", dc) == "hello"
    end

    test "nil transform key is a no-op" do
      dc = %{"transform" => nil}
      assert Transform.resolve("hello", dc) == "hello"
    end
  end

  describe "resolve/2 — pipeline (list of transforms)" do
    test "applies transforms left-to-right" do
      Application.put_env(:attr_engine, :transforms, %{
        "append_bang" => fn value -> value <> "!" end,
        "upcase" => &String.upcase/1
      })

      dc = %{"transform" => ["upcase", "append_bang"]}
      assert Transform.resolve("hello", dc) == "HELLO!"

      Application.delete_env(:attr_engine, :transforms)
    end
  end

  describe "resolve/2 — external function transforms" do
    setup do
      on_exit(fn -> Application.delete_env(:attr_engine, :transforms) end)
    end

    test "1-arity function transform" do
      Application.put_env(:attr_engine, :transforms, %{
        "upcase" => &String.upcase/1
      })

      dc = %{"transform" => "upcase"}
      assert Transform.resolve("hello", dc) == "HELLO"
    end

    test "2-arity function receives data_config as second arg" do
      Application.put_env(:attr_engine, :transforms, %{
        "prefix" => fn value, opts -> (opts["prefix"] || "") <> to_string(value) end
      })

      dc = %{"transform" => "prefix", "prefix" => "KEY: "}
      assert Transform.resolve("abc", dc) == "KEY: abc"
    end

    test "external transforms override built-ins" do
      Application.put_env(:attr_engine, :transforms, %{
        "redact" => fn _value -> "CUSTOM_REDACT" end
      })

      dc = %{"transform" => "redact"}
      assert Transform.resolve("secret", dc) == "CUSTOM_REDACT"
    end
  end

  describe "resolve/2 — module-based transforms" do
    test "module implementing the behaviour is called" do
      dc = %{"transform" => "redact_secret"}
      assert Transform.resolve("some_secret_value", dc) == "[provided]"
      assert Transform.resolve(nil, dc) == "[not set]"
      assert Transform.resolve("", dc) == "[not set]"
    end
  end

  describe "apply_transforms/2" do
    test "transforms only attributes with a declared transform" do
      attrs_meta = [
        %{handle: "name", data_config: %{"type" => "binary"}},
        %{handle: "credential", data_config: %{"type" => "binary", "transform" => "redact_secret"}}
      ]

      data = %{"name" => "My App", "credential" => "some_opaque_value"}
      result = Transform.apply_transforms(attrs_meta, data)

      assert result["name"] == "My App"
      assert result["credential"] == "[provided]"
    end

    test "handles nil values in data" do
      attrs_meta = [
        %{handle: "token", data_config: %{"transform" => "redact_secret"}}
      ]

      data = %{"token" => nil}
      result = Transform.apply_transforms(attrs_meta, data)
      assert result["token"] == "[not set]"
    end

    test "handles missing keys in data" do
      attrs_meta = [
        %{handle: "token", data_config: %{"transform" => "redact"}}
      ]

      data = %{}
      result = Transform.apply_transforms(attrs_meta, data)
      assert result["token"] == nil
    end
  end

  describe "Redact transform" do
    test "masks non-nil values" do
      assert AttrEngine.Transform.Redact.apply("secret", %{}) == "••••••••"
      assert AttrEngine.Transform.Redact.apply(12345, %{}) == "••••••••"
      assert AttrEngine.Transform.Redact.apply(%{key: "val"}, %{}) == "••••••••"
    end

    test "preserves nil" do
      assert AttrEngine.Transform.Redact.apply(nil, %{}) == nil
    end
  end

  describe "RedactSecret transform" do
    test "indicates presence for non-nil, non-empty values" do
      assert AttrEngine.Transform.RedactSecret.apply("some_opaque_value", %{}) == "[provided]"
      assert AttrEngine.Transform.RedactSecret.apply(true, %{}) == "[provided]"
    end

    test "indicates absence for nil and empty string" do
      assert AttrEngine.Transform.RedactSecret.apply(nil, %{}) == "[not set]"
      assert AttrEngine.Transform.RedactSecret.apply("", %{}) == "[not set]"
    end
  end

  describe "lookup/1" do
    setup do
      on_exit(fn -> Application.delete_env(:attr_engine, :transforms) end)
    end

    test "returns built-in module for known name" do
      assert Transform.lookup("redact") == AttrEngine.Transform.Redact
      assert Transform.lookup("redact_secret") == AttrEngine.Transform.RedactSecret
    end

    test "returns nil for unknown name" do
      assert Transform.lookup("unknown") == nil
    end

    test "external config takes precedence" do
      custom = fn _v -> "custom" end
      Application.put_env(:attr_engine, :transforms, %{"redact" => custom})
      assert Transform.lookup("redact") == custom
    end
  end
end
