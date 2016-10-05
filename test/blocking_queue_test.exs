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

  test "BlockingQueue empty? should test if the queue is empty" do
    {:ok, pid} = BlockingQueue.start_link(5)
    assert true == BlockingQueue.empty?(pid)
    BlockingQueue.push(pid, "Hello")
    assert false == BlockingQueue.empty?(pid)
    BlockingQueue.pop(pid)
    assert true == BlockingQueue.empty?(pid)
  end

  test "BlockingQueue size should return the length of the queue" do
    {:ok, pid} = BlockingQueue.start_link(5)
    assert 0 == BlockingQueue.size(pid)
    BlockingQueue.push(pid, "Hello")
    assert 1 == BlockingQueue.size(pid)
    BlockingQueue.push(pid, "World")
    assert 2 == BlockingQueue.size(pid)
    BlockingQueue.pop(pid)
    assert 1 == BlockingQueue.size(pid)
    BlockingQueue.pop(pid)
    assert 0 == BlockingQueue.size(pid)
  end

  test "BlockingQueue member? should test if an item is in the queue" do
    {:ok, pid} = BlockingQueue.start_link(5)
    BlockingQueue.push(pid, "Hello")
    assert true == BlockingQueue.member?(pid, "Hello")
    assert false == BlockingQueue.member?(pid, "World")
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

  test "BlockingQueue pop on empty queue can wait beyond GenServer call timeout" do
    {:ok, pid} = BlockingQueue.start_link(5)

    task = Task.async(fn -> BlockingQueue.pop(pid, 5)end)
    ref = Process.monitor(task.pid)

    :timer.sleep 10
    BlockingQueue.push pid, "Hello"
    assert_receive {:DOWN, ^ref, :process, _, :normal}, 100
  end

  test "BlockingQueue push on full queue can wait beyond GenServer call timeout" do
    {:ok, pid} = BlockingQueue.start_link(1)

    BlockingQueue.push pid, "Hello"

    task = Task.async(fn -> BlockingQueue.push(pid, "World", 5)end)
    ref = Process.monitor(task.pid)

    :timer.sleep 10
    assert "Hello" == BlockingQueue.pop pid
    assert_receive {:DOWN, ^ref, :process, _, :normal}, 100
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

  test "BlockingQueue can have more than one client waiting to pop from an empty queue" do
    {:ok, pid} = BlockingQueue.start_link(1)

    task1 = Task.async(fn -> BlockingQueue.pop(pid) end)
    task2 = Task.async(fn -> BlockingQueue.pop(pid) end)

    # @cboggs: This test passes falsely if this sleep is not present. I suspect this is due to `task2` failing before `ref2` can monitor it, which (by itself) does not in cause a failure
    :timer.sleep 1

    ref1 = Process.monitor(task1.pid)
    ref2 = Process.monitor(task2.pid)

    BlockingQueue.push(pid, "Hello")
    BlockingQueue.push(pid, "World")

    assert_receive {:DOWN, ^ref1, :process, _, :normal}, 100
    assert_receive {:DOWN, ^ref2, :process, _, :normal}, 100
  end

  test "BlockingQueue can have more than one client waiting to push to a full queue" do
    {:ok, pid} = BlockingQueue.start_link(1)
    BlockingQueue.push(pid, "Hello")

    task1 = Task.async(fn -> BlockingQueue.push(pid, "Awesome") end)
    task2 = Task.async(fn -> BlockingQueue.push(pid, "World") end)

    # @cboggs: This test passes falsely if this sleep is not present. I suspect this is due to `task2` failing before `ref2` can monitor it, which (by itself) does not in cause a failure
    :timer.sleep 1

    ref1 = Process.monitor(task1.pid)
    ref2 = Process.monitor(task2.pid)

    BlockingQueue.pop(pid)
    BlockingQueue.pop(pid)

    assert_receive {:DOWN, ^ref1, :process, _, :normal}, 100
    assert_receive {:DOWN, ^ref2, :process, _, :normal}, 100
  end

  test "BlockingQueue returns results to multiple push waiters in LIFO order" do
    {:ok, pid} = BlockingQueue.start_link(1)
    range = 1..10
    expected_result = Enum.into(range, [])

    # tiny sleep included to make absolutely sure we spawn waiters in the right order
    for item <- range do
      Task.async(fn ->
        BlockingQueue.push(pid, item)
      end);
      :timer.sleep 1
    end

    assert expected_result == Enum.into(range, [], fn _ -> BlockingQueue.pop(pid) end)
  end

  test "BlockingQueue should filter the queue according to the provided function" do
    {:ok, pid} = BlockingQueue.start_link(5)
    BlockingQueue.push(pid, "Hello")
    BlockingQueue.push(pid, "World")
    BlockingQueue.push(pid, "There")
    BlockingQueue.push(pid, "World")
    BlockingQueue.filter(pid, &( &1 != "World"))
    assert false == BlockingQueue.member?(pid, "World")
    assert 2 == BlockingQueue.size(pid)
    assert "Hello" == BlockingQueue.pop(pid)
    assert "There" == BlockingQueue.pop(pid)
  end

  test "BlockingQueue should handle push waiters when filtering" do
    {:ok, pid} = BlockingQueue.start_link(3)
    BlockingQueue.push(pid, "Hello")
    BlockingQueue.push(pid, "World")
    BlockingQueue.push(pid, "World")

    task1 = Task.async(fn -> BlockingQueue.push(pid, "There") end)
    task2 = Task.async(fn -> BlockingQueue.push(pid, "World") end)
    task3 = Task.async(fn -> BlockingQueue.push(pid, "Again") end)

    # @cboggs: This test passes falsely if this sleep is not present. I suspect this is due to `task2` failing before `ref2` can monitor it, which (by itself) does not in cause a failure
    :timer.sleep 1

    ref1 = Process.monitor(task1.pid)
    ref2 = Process.monitor(task2.pid)
    ref3 = Process.monitor(task3.pid)

    BlockingQueue.filter(pid, &( &1 != "World"))

    assert_receive {:DOWN, ^ref1, :process, _, :normal}, 100
    assert_receive {:DOWN, ^ref2, :process, _, :normal}, 100
    assert_receive {:DOWN, ^ref3, :process, _, :normal}, 100

    assert false == BlockingQueue.member?(pid, "World")
    assert 3 == BlockingQueue.size(pid)
    assert "Hello" == BlockingQueue.pop(pid)
    assert "There" == BlockingQueue.pop(pid)
    assert "Again" == BlockingQueue.pop(pid)
  end

end
