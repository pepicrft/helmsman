defmodule Helmsman.Tools.ReadTest do
  use ExUnit.Case, async: true

  alias Helmsman.Tools.Read

  @moduletag :tmp_dir

  test "reads file contents", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "test.txt")
    File.write!(path, "Hello, World!")

    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Read.call(%{"path" => "test.txt"}, context)

    assert is_binary(result)
    assert result == "Hello, World!"
  end

  test "reads with offset and limit", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "lines.txt")
    File.write!(path, "line1\nline2\nline3\nline4\nline5")

    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Read.call(%{"path" => "lines.txt", "offset" => 2, "limit" => 2}, context)

    assert String.contains?(result, "line2")
    assert String.contains?(result, "line3")
    refute String.contains?(result, "line1")
    refute String.contains?(result, "line4")
  end

  test "returns error for missing file", %{tmp_dir: tmp_dir} do
    context = %{cwd: tmp_dir, opts: []}
    {:error, error} = Read.call(%{"path" => "missing.txt"}, context)

    assert String.contains?(error, "not found")
  end

  test "returns error for directory", %{tmp_dir: tmp_dir} do
    context = %{cwd: tmp_dir, opts: []}
    {:error, error} = Read.call(%{"path" => "."}, context)

    assert String.contains?(error, "directory")
  end

  test "returns image content for image files", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "pixel.png")

    png_data =
      Base.decode64!("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2Z0AAAAASUVORK5CYII=")

    File.write!(path, png_data)

    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Read.call(%{"path" => "pixel.png"}, context)

    assert %{
             type: :image,
             media_type: "image/png",
             data: encoded_data
           } = result

    assert Base.decode64!(encoded_data) == png_data
  end

  test "maps supported image extensions to media types", %{tmp_dir: tmp_dir} do
    image_files = [
      {"sample.jpg", "image/jpeg"},
      {"sample.jpeg", "image/jpeg"},
      {"sample.png", "image/png"},
      {"sample.gif", "image/gif"},
      {"sample.webp", "image/webp"}
    ]

    context = %{cwd: tmp_dir, opts: []}

    for {filename, media_type} <- image_files do
      File.write!(Path.join(tmp_dir, filename), "image-bytes")

      {:ok, result} = Read.call(%{"path" => filename}, context)

      assert %{type: :image, media_type: ^media_type, data: encoded_data} = result
      assert Base.decode64!(encoded_data) == "image-bytes"
    end
  end
end
