defmodule AttrEngine.Transform.RedactSecret do
  @moduledoc """
  Replaces secret values with a presence indicator.

  Unlike `Redact`, this transform distinguishes between "a value exists"
  and "no value has been set", which is critical for credential UIs where
  the user needs to know whether a key is configured without seeing it.

  - Non-nil/non-empty values become `"[provided]"`
  - Nil or empty string becomes `"[not set]"`
  """
  @behaviour AttrEngine.Transform

  @impl true
  def apply(nil, _opts), do: "[not set]"
  def apply("", _opts), do: "[not set]"
  def apply(_value, _opts), do: "[provided]"
end
