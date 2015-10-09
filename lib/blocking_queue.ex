defmodule BlockingQueue do
  @moduledoc """
  BlockingQueue is a simple queue implemented as a GenServer.  It has a fixed
  maximum length.

  The queue is designed to decouple but limit the latency of a producer and
  consumer.  When pushing to a full queue the `push` operation blocks
  preventing the producer from making progress until the consumer catches up.
  Likewise, when calling `pop` on an empty queue the call blocks until there
  is work to do.

  ## Examples

      {:ok, pid} = BlockingQueue.start_link(5)
      BlockingQueue.push(pid, "Hi")
      BlockingQueue.pop(pid) # should return "Hi"
  """
  use GenServer

  # Can I get this from somewhere?
  @type on_start :: {:ok, pid} | :ignore | {:error, {:already_started, pid} | term}

  @doc """
  Start a queue process with GenServer.start_link/2.

  `n` Is the maximum queue depth.
  """
  @spec start_link(pos_integer()) :: on_start
  def start_link(n), do: GenServer.start_link(__MODULE__, n)
  def init(n), do: {:ok, {n, []}}

  @typep from_t   :: {pid, any}
  @typep state_t  :: {pos_integer(), [any]}
                   | {pos_integer(), [any], :pop, from_t}
                   | {pos_integer(), [any], :push, from_t, any}
  @typep call_t   :: {:push, any}
                   | :pop
  @typep result_t :: {:reply, any, state_t}
                   | {:noreply, state_t}

  @spec handle_call(call_t, from_t, state_t) :: result_t

  def handle_call({:push, item}, waiter, {max, list}) when length(list) >= max do
    {:noreply, {max, list, :push, waiter, item}}
  end

  def handle_call({:push, item}, _, {max, list}) do
    {:reply, nil, { max, list ++ [item] }}
  end

  def handle_call({:push, item}, _, {max, [], :pop, from}) do
    GenServer.reply(from, item)
    {:reply, nil, {max, []}}
  end

  def handle_call(:pop, from, {max, []}), do: {:noreply, {max, [], :pop, from}}
  def handle_call(:pop, _, {max, [x | xs]}), do: {:reply, x, {max, xs}}
  def handle_call(:pop, _, {max, [x | xs], :push, waiter, item}) do
    GenServer.reply(waiter, nil)
    {:reply, x, {max, xs ++ [item]}}
  end

  @doc """
  Pushes a new item into the queue.  Blocks if the queue is full.

  `pid` is the process ID of the BlockingQueue server.
  `item` is the value to be pushed into the queue.  This can be anything.
  """
  @spec push(pid, any) :: nil
  def push(pid, item), do: GenServer.call(pid, {:push, item})

  @doc """
  Pops the least recently pushed item from the queue. Blocks if the queue is
  empty until an item is available.

  `pid` is the process ID of the BlockingQueue server.
  """
  @spec pop(pid) :: any
  def pop(pid), do: GenServer.call(pid, :pop)

  @doc """
  Pushes all items in a stream into the blocking queue.  Blocks as necessary.

  `stream` is the the stream of values to push into the queue.
  `pid` is the process ID of the BlockingQueue server.
  """
  @spec push_stream(Enumerable.t, pid) :: nil
  def push_stream(stream, pid) do
    spawn_link(fn ->
      Enum.each(stream, &push(pid, &1))
    end)
    nil
  end

  @doc """
  Returns a Stream where each element comes from the BlockingQueue.

  `pid` is the process ID of the BlockingQueue server.
  """
  @spec pop_stream(pid) :: Enumerable.t
  def pop_stream(pid) do
    Stream.repeatedly(fn -> BlockingQueue.pop(pid) end)
  end
end
