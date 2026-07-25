defmodule AttrEngine.Transform do
  @moduledoc """
  Render-time value transforms.

  Transforms modify attribute values at resolution/render time before they
  reach consumers. Declare a transform on any attribute via its
  `data_config["transform"]` key (a string name or list of string names).

  ## Built-in transforms

  - `"redact"` — replaces any non-nil value with `"••••••••"`
  - `"redact_secret"` — replaces non-nil with `"[provided]"`, returns `"[not set]"` for nil

  ## Registering custom transforms

  Implement the `AttrEngine.Transform` behaviour and register via application config:

      config :attr_engine, transforms: %{
        "currency" => MyApp.Transforms.Currency
      }

  Or supply a function (arity 1 or 2):

      config :attr_engine, transforms: %{
        "upcase" => &String.upcase/1,
        "prefix" => fn value, opts -> opts["prefix"] <> value end
      }

  External transforms take precedence over built-ins with the same name.

  ## Behaviour

  Modules implementing this behaviour must define `apply/2`:

      defmodule MyApp.Transforms.Currency do
        @behaviour AttrEngine.Transform

        @impl true
        def apply(value, _opts) when is_number(value) do
          :erlang.float_to_binary(value / 1.0, decimals: 2)
        end
        def apply(value, _opts), do: value
      end

  The second argument (`opts`) is the full `data_config` map for the attribute,
  allowing transforms to read additional configuration keys.
  """

  @doc "Apply a transform to a value. Receives the raw value and the attribute's data_config."
  @callback apply(value :: any(), opts :: map()) :: any()

  @builtins %{
    "redact" => AttrEngine.Transform.Redact,
    "redact_secret" => AttrEngine.Transform.RedactSecret
  }

  @doc """
  Applies the declared transform(s) for an attribute to its value.

  Reads `data_config["transform"]` which may be:
  - a string (single transform name)
  - a list of strings (pipeline, applied left-to-right)
  - nil (no-op, returns value unchanged)

  Returns the transformed value.
  """
  @spec resolve(any(), map()) :: any()
  def resolve(value, data_config) do
    case Map.get(data_config, "transform") do
      nil -> value
      name when is_binary(name) -> apply_one(value, name, data_config)
      names when is_list(names) -> Enum.reduce(names, value, &apply_one(&2, &1, data_config))
      _ -> value
    end
  end

  @doc """
  Applies transforms across a map of data using resolved attrs_meta.

  For each attribute in `attrs_meta` that declares a transform in its
  `data_config`, the corresponding value in `data` is transformed.

  Returns the data map with transformed values.
  """
  @spec apply_transforms([map()], map()) :: map()
  def apply_transforms(attrs_meta, data) do
    Enum.reduce(attrs_meta, data, fn %{handle: handle, data_config: dc}, acc ->
      case Map.get(dc, "transform") do
        nil ->
          acc

        _ ->
          value = Map.get(acc, handle)
          Map.put(acc, handle, resolve(value, dc))
      end
    end)
  end

  @doc """
  Looks up a named transform. Returns the module or function, or nil.

  Resolution order: external config > built-ins.
  """
  @spec lookup(String.t()) :: module() | function() | nil
  def lookup(name) when is_binary(name) do
    externals = Application.get_env(:attr_engine, :transforms, %{})
    Map.get(externals, name) || Map.get(@builtins, name)
  end

  defp apply_one(value, name, data_config) do
    case lookup(name) do
      nil ->
        value

      fun when is_function(fun, 1) ->
        fun.(value)

      fun when is_function(fun, 2) ->
        fun.(value, data_config)

      module when is_atom(module) ->
        module.apply(value, data_config)
    end
  end
end
