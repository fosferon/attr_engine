defmodule AttrEngine.Helpers.CustomAttributes do
  @moduledoc """
  Helper functions for managing custom attributes stored in JSONB fields.

  For entities that embed attribute data directly (rather than via ASD),
  this module provides get/put/validate helpers.

  The JSONB structure is:

      %{
        "attribute_set_id_1" => %{"field_a" => "value1", "field_b" => 42},
        "attribute_set_id_2" => %{"field_c" => true}
      }

  Top-level keys are attribute set IDs, values are maps of handle → value.
  """

  @doc "Get a single custom attribute value."
  @spec get(map() | struct(), String.t(), String.t()) :: any()
  def get(entity, attribute_set_id, handle) do
    entity
    |> custom_attrs()
    |> Map.get(attribute_set_id, %{})
    |> Map.get(handle)
  end

  @doc "Set a single custom attribute value. Returns updated entity."
  @spec put(struct(), String.t(), String.t(), any()) :: struct()
  def put(entity, attribute_set_id, handle, value) do
    updated_set =
      entity
      |> custom_attrs()
      |> Map.get(attribute_set_id, %{})
      |> Map.put(handle, value)

    updated = Map.put(custom_attrs(entity), attribute_set_id, updated_set)
    %{entity | custom_attributes: updated}
  end

  @doc "Get all custom attributes for a given attribute set."
  @spec get_set(map() | struct(), String.t()) :: map()
  def get_set(entity, attribute_set_id) do
    Map.get(custom_attrs(entity), attribute_set_id, %{})
  end

  @doc "Set all custom attributes for a given attribute set."
  @spec put_set(struct(), String.t(), map()) :: struct()
  def put_set(entity, attribute_set_id, set_data) do
    updated = Map.put(custom_attrs(entity), attribute_set_id, set_data)
    %{entity | custom_attributes: updated}
  end

  # Resolve the custom attributes map from entity — supports both
  # :custom_attributes and :data fields
  defp custom_attrs(entity) when is_map(entity) do
    cond do
      is_map(Map.get(entity, :custom_attributes)) and
          map_size(Map.get(entity, :custom_attributes, %{})) > 0 ->
        entity.custom_attributes

      is_map(Map.get(entity, :data)) ->
        entity.data

      true ->
        %{}
    end
  end
end
