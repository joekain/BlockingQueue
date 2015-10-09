defmodule BlockingQueueTest do
  use ExUnit.Case
  use ExCheck

  test "BlockingQueue is started with a maximum depth" do
    {:ok, _pid} = BlockingQueue.start_link(5)
  end

  test "BlockingQueue can push" do
    {:ok, pid} = BlockingQueue.start_link(5)
    BlockingQueue.push(pid, "Hi")
  end

  test "BlockingQueue pop should return the last push" do
    item = "Hi"
    {:ok, pid} = BlockingQueue.start_link(5)
    BlockingQueue.push(pid, item)
    assert item == BlockingQueue.pop(pid)
  end

  test "BlockingQueue push/pop should be first in / first out" do
    {:ok, pid} = BlockingQueue.start_link(5)
    BlockingQueue.push(pid, "Hello")
    BlockingQueue.push(pid, "World")
    assert "Hello" == BlockingQueue.pop(pid)
    assert "World" == BlockingQueue.pop(pid)
  end

  test "BlockingQueue should be able to accept a Stream of values" do
    {:ok, pid} = BlockingQueue.start_link(5)

    ["hello", "world"]
    |> Stream.map(&String.upcase/1)
    |> BlockingQueue.push_stream(pid)

    assert "HELLO" == BlockingQueue.pop(pid)
    assert "WORLD" == BlockingQueue.pop(pid)
  end

  test "BlockingQueue shoud return a Stream of values" do
    {:ok, pid} = BlockingQueue.start_link(5)

    BlockingQueue.push(pid, "Hello")
    BlockingQueue.push(pid, "World")

    list = BlockingQueue.pop_stream(pid) |> Enum.take(2)
    assert list == ["Hello", "World"]
  end

  test "BlockingQueue can be infinite" do
    {:ok, pid} = BlockingQueue.start_link(:infinity)

    BlockingQueue.push(pid, "Hello")
    BlockingQueue.push(pid, "World")

    list = BlockingQueue.pop_stream(pid) |> Enum.take(2)
    assert list == ["Hello", "World"]
  end

  property "BlockingQueue supports async and blocking pushes and pops" do
    for_all xs in list(int) do
      implies length(xs) > 0 do
        {:ok, pid} = BlockingQueue.start_link(5)
        Task.async(fn ->
          Enum.map(xs, fn x -> BlockingQueue.push(pid, x) end)
        end)

        puller = Task.async(fn ->
          Enum.map(xs, fn _ -> BlockingQueue.pop(pid) end)
        end)

        Task.await(puller) == xs
      end
    end
  end

  property "BlockingQueue stream API supports blocking pushes and pops" do
    for_all xs in list(int) do
      implies length(xs) > 0 do
        {:ok, pid} = BlockingQueue.start_link(5)

        BlockingQueue.push_stream(xs, pid)

        assert xs == BlockingQueue.pop_stream(pid)
        |> Enum.take(Enum.count(xs))
      end
    end
  end
end
