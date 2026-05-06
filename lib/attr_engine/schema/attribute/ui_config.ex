defmodule AttrEngine.Schema.Attribute.UIConfig do
  @moduledoc """
  Embedded schema for the UI-side configuration of an Attribute.

  Controls how an attribute is presented and interacted with in backend UIs:
  input type, editability, visibility, custom view/edit modules, and
  identifier locking.

  ## Fields

  - `type` — HTML input type (e.g. `"text"`, `"select"`, `"textarea"`)
  - `editable?` — whether the attribute is editable in forms
  - `hidden?` — whether the attribute is hidden from the UI
  - `custom_view?` — whether a custom view module is used
  - `edit_params` / `view_params` — parameter maps for edit/view modules
  - `edit_module` / `view_module` — function-call specification maps
  - `lock_handle?` / `lock_code?` — prevent modification of handle/code
    on persisted records
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type :binary_id

  @input_types ~w(
    checkbox color date datetime-local email file hidden month
    number password range radio search select tel text textarea time url week
  )

  embedded_schema do
    field :type, :string
    field :custom_view?, :boolean, default: false
    field :editable?, :boolean, default: true
    field :edit_params, :map, default: %{}
    field :hidden?, :boolean, default: false
    field :view_params, :map, default: %{}
    field :lock_handle?, :boolean, default: true
    field :lock_code?, :boolean, default: true
    field :edit_module, :map
    field :view_module, :map
  end

  @cast_fields ~w(type custom_view? editable? edit_params hidden? view_params lock_handle? lock_code? edit_module view_module)a

  @doc "Standard changeset — validates required fields and input type inclusion."
  def changeset(ui_config, attrs) do
    ui_config
    |> cast(attrs, @cast_fields)
    |> validate_required([:type, :custom_view?, :editable?, :hidden?, :lock_handle?, :lock_code?])
    |> validate_inclusion(:type, ["" | @input_types])
  end

  @doc "Returns the list of supported input type options."
  @spec input_type_options() :: [{String.t(), String.t()}]
  def input_type_options do
    [{"None", ""} | Enum.map(@input_types, fn t -> {String.capitalize(t), t} end)]
  end
end
