defmodule AttrEngine.Transform.Redact do
  @moduledoc """
  Replaces any non-nil value with a masked placeholder.

  Useful for attributes that should never expose their raw value in
  rendered output (e.g. API tokens displayed in a settings UI).

  Returns `"••••••••"` for non-nil values, `nil` for nil.
  """
  @behaviour AttrEngine.Transform

  @placeholder "••••••••"

  @impl true
  def apply(nil, _opts), do: nil
  def apply(_value, _opts), do: @placeholder
end
