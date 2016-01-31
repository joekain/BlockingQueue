defmodule BlockingQueue do
  @moduledoc """
  BlockingQueue is a simple queue implemented as a GenServer.  It has a fixed
  maximum length.

  The queue is designed to decouple but limit the latency of a producer and
  consumer.  When pushing to a full queue the `push` operation blocks
  preventing the producer from making progress until the consumer catches up.
  Likewise, when calling `pop` on an empty queue the call blocks until there
  is work to do.

  ## Protocols

  The BlockingQueue module implements the `Collectable` protocol.

  ## Examples

      {:ok, pid} = BlockingQueue.start_link(5)
      BlockingQueue.push(pid, "Hi")
      BlockingQueue.pop(pid) # should return "Hi"

      {:ok, pid} = BlockingQueue.start_link(:infinity)
      BlockingQueue.push(pid, "Hi")
      BlockingQueue.pop(pid) # should return "Hi"
  """
  use GenServer

  @empty_queue :queue.new
  @typep queue_t :: {[any], [any]}

  @typedoc """
  The `%BlockingQueue` struct is used with the `Collectable` protocol.

  ## Examples

      input = ["Hello", "World"]
      {:ok, pid} = BlockingQueue.start_link(5)
      Enum.into(input, %BlockingQueue{pid: pid})
      BlockingQueue.pop_stream(pid) |> Enum.take(2)  # should return input
  """
  defstruct pid: nil
  @type t :: %BlockingQueue{pid: pid()}

  # Can I get this from somewhere?
  @type on_start :: {:ok, pid} | :ignore | {:error, {:already_started, pid} | term}

  @doc """
  Start a queue process with GenServer.start_link/3.

  `n` Is the maximum queue depth.  Pass the atom `:infinity` to start a queue
  with no maximum.  An infinite queue will never block in `push/2` but may
  block in `pop/1`

  `options` Are options as described for `GenServer.start_link/3` and are optional.
  """
  @type maximum_t :: pos_integer()
                   | :infinity
  @spec start_link(maximum_t, [any]) :: on_start
  def start_link(n, options \\ []), do: GenServer.start_link(__MODULE__, n, options)
  def init(n), do: {:ok, {n, @empty_queue}}

  @typep from_t   :: {pid, any}
  @typep state_t  :: {pos_integer(), queue_t}
                   | {pos_integer(), queue_t, :pop, from_t}
                   | {pos_integer(), queue_t, :push, from_t, any}
  @typep call_t   :: {:push, any}
                   | :pop
  @typep result_t :: {:reply, any, state_t}
                   | {:noreply, state_t}

  @spec handle_call(call_t, from_t, state_t) :: result_t

  def handle_call({:push, item}, waiter, {max, queue={left,right}}) when length(left) + length(right) >= max do
    {:noreply, {max, queue, :push, waiter, item}}
  end

  def handle_call({:push, item}, _, {max, queue}) do
    {:reply, nil, { max, :queue.in(item, queue) }}
  end

  def handle_call({:push, item}, _, {max, @empty_queue, :pop, [next|[]]}) do
    GenServer.reply(next, item)
    {:reply, nil, {max, @empty_queue}}
  end

  def handle_call({:push, item}, _, {max, @empty_queue, :pop, [next|rest]}) do
    GenServer.reply(next, item)
    {:reply, nil, {max, @empty_queue, :pop, rest}}
  end

  def handle_call(:pop, from, {max, @empty_queue}) do
    {:noreply, {max, @empty_queue, :pop, [from]}}
  end

  def handle_call(:pop, from, {max, @empty_queue, :pop, [next|rest]}) do
    {:noreply, {max, @empty_queue, :pop, [from|[next|rest]]}}
  end

  def handle_call(:pop, _, {max, queue}) do
    {{:value, popped_item}, new_queue} = :queue.out(queue)
    {:reply, popped_item, {max, new_queue}}
  end

  def handle_call(:pop, _, {max, queue, :push, waiter, item}) do
    GenServer.reply(waiter, nil)
    {{:value, popped_item}, popped_queue} = :queue.out(queue)
    final_queue = :queue.in(item, popped_queue)
    {:reply, popped_item, {max, final_queue}}
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
