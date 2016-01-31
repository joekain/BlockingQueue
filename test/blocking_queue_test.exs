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

  test "BlockingQueue should implement Collectable" do
    input = ["Hello", "World"]

    {:ok, pid} = BlockingQueue.start_link(5)
    Enum.into(input, %BlockingQueue{pid: pid})

    assert input == BlockingQueue.pop_stream(pid) |> Enum.take(2)
  end

  test "BlockingQueue should not die after GenServer's default 5000ms when poping from an empty queue" do
    {:ok, pid} = BlockingQueue.start_link(1)

    task = Task.async(fn ->
      BlockingQueue.pop pid
    end)

    ref = Process.monitor(task.pid)
    :timer.sleep 6000
    BlockingQueue.push pid, "Hello"
    assert_receive {:DOWN, ^ref, :process, _, :normal}, 10000
  end

  test "BlockingQueue should not die after GenServer's default 5000ms when pushing to a full queue" do
    {:ok, pid} = BlockingQueue.start_link(1)
    BlockingQueue.push pid, "Hello"

    task = Task.async(fn ->
      BlockingQueue.push pid, "World"
    end)

    ref = Process.monitor(task.pid)
    :timer.sleep 6000
    BlockingQueue.pop pid
    assert_receive {:DOWN, ^ref, :process, _, :normal}, 10000
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
