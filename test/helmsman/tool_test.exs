defmodule Helmsman.ToolTest do
  use ExUnit.Case, async: true

  alias Helmsman.Tool
  alias Helmsman.Tools.Read

  test "builds spec from module" do
    spec = Tool.to_spec(Read)

    assert spec.name == "Read"
    assert is_binary(spec.description)
    assert is_map(spec.parameters)
  end
end
