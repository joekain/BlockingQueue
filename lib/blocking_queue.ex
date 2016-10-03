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

  # start a list of waiting pushers when the first client tries to push to a full queue
  def handle_call({:push, item}, from, {max, queue={left,right}}) when length(left) + length(right) >= max do
    {:reply, :block, {max, queue, :push, [{from, item}]}}
  end

  # prepend new waiter to list of waiting pushers when they try to push to a full queue
  def handle_call({:push, item}, from, {max, queue={left,right}, :push, [next|rest]}) when length(left) + length(right) >= max do
    {:reply, :block, {max, queue, :push, [{from, item} | [next|rest]] }}
  end

  def handle_call({:push, item}, _, {max, queue}) do
    {:reply, nil, { max, :queue.in(item, queue) }}
  end

  # send item to a single waiting popper 
  def handle_call({:push, item}, _, {max, @empty_queue, :pop, [next|[]]}) do
    send elem(next, 0), {:awaken, item}
    {:reply, nil, {max, @empty_queue}}
  end

  # send item to the next in a list of waiting poppers
  def handle_call({:push, item}, _, {max, @empty_queue, :pop, [next|rest]}) do
    send elem(next, 0), {:awaken, item}
    {:reply, nil, {max, @empty_queue, :pop, rest}}
  end

  # start a list of waiting poppers when the first client tries to pop from the empty queue
  def handle_call(:pop, from, {max, @empty_queue}) do
    {:reply, :block, {max, @empty_queue, :pop, [from]}}
  end

  # prepend new waiter to list of waiting poppers when they try to pop from an empty queue
  def handle_call(:pop, from, {max, @empty_queue, :pop, [next|rest]}) do
    {:reply, :block, {max, @empty_queue, :pop, [from | [next|rest]]}}
  end

  # accept an item pushed by a single waiting pusher
  def handle_call(:pop, _, {max, queue, :push, [{next, item}] }) do
    {{:value, popped_item}, popped_queue} = :queue.out(queue)
    send elem(next, 0), :awaken
    final_queue = :queue.in(item, popped_queue)
    {:reply, popped_item, {max, final_queue}}
  end

  # accept an item pushed by the last in a list of waiting pushers (taking last makes this FIFO)
  def handle_call(:pop, _, {max, queue, :push, waiters}) when is_list waiters do
    {{:value, popped_item}, popped_queue} = :queue.out(queue)
    {next, item} = List.last waiters
    rest = List.delete_at waiters, -1
    send elem(next, 0), :awaken
    final_queue = :queue.in(item, popped_queue)
    {:reply, popped_item, {max, final_queue, :push, rest}}
  end

  def handle_call(:pop, _, {max, queue}) do
    {{:value, popped_item}, new_queue} = :queue.out(queue)
    {:reply, popped_item, {max, new_queue}}
  end

  # determine is the queue is empty
  def handle_call(:is_empty, _, s) do
    {:reply, :queue.is_empty(elem(s, 1)), s}
  end

  # determine the length of the queue
  def handle_call(:len, _, s) do
    {:reply, :queue.len(elem(s, 1)), s}
  end

  # check if an item is in the queue
  def handle_call({:member, item}, _, s) do
    {:reply, :queue.member(item, elem(s, 1)), s}
  end

  # remove all items using predicate function
  def handle_call({:filter, f}, _, {max, queue}) do
    {:reply, nil, {max, :queue.filter(f, queue)}}
  end

  # remove all items using predicate function, handling push waiters
  def handle_call({:filter, f}, _, {max, queue, :push, waiters}) when is_list waiters do
    filtered_queue = :queue.filter(f, queue)
    {still_waiters, filtered_waiters} = Enum.partition waiters, &f.(elem(&1, 1))
    Enum.each filtered_waiters, &send(elem(elem(&1, 0), 0), :awaken)
    {rest, next} = Enum.split still_waiters, :queue.len(filtered_queue) - max
    final_queue = Enum.reduce(Enum.reverse(next), filtered_queue, fn({next, item}, q) -> 
      send(elem(next, 0), :awaken)
      :queue.in(item, q) 
    end)
    {:reply, nil, (if Enum.empty?(rest), do: {max, final_queue}, else: {max, final_queue, :push, rest}) }
  end

  @doc """
  Pushes a new item into the queue.  Blocks if the queue is full.

  `pid` is the process ID of the BlockingQueue server.
  `item` is the value to be pushed into the queue.  This can be anything.
  `timeout` (optional) is the timeout value passed to GenServer.call (does not impact how long pop will wait for a message from the queue)
  """
  @spec push(pid, any, integer) :: nil
  def push(pid, item, timeout \\ 5000) do
    case GenServer.call(pid, {:push, item}, timeout) do
      :block ->
        receive do
          :awaken -> :ok
        end
      _ -> nil
    end
  end

  @doc """
  Pops the least recently pushed item from the queue. Blocks if the queue is
  empty until an item is available.

  `pid` is the process ID of the BlockingQueue server.
  `timeout` (optional) is the timeout value passed to GenServer.call (does not impact how long pop will wait for a message from the queue)
  """
  @spec pop(pid, integer) :: any
  def pop(pid, timeout \\ 5000) do
    case GenServer.call(pid, :pop, timeout) do
      :block ->
        receive do
          {:awaken, data} -> data
        end
      data -> data
    end
  end

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


  @doc """
  Tests if the queue is empty and returns true if so, otherwise false.

  `pid` is the process ID of the BlockingQueue server.
  """
  @spec empty?(pid, integer) :: boolean
  def empty?(pid, timeout \\ 5000) do
    GenServer.call(pid, :is_empty, timeout)
  end

  @doc """
  Calculates and returns the number of items in the queue.

  `pid` is the process ID of the BlockingQueue server.
  """
  @spec size(pid, integer) :: non_neg_integer
  def size(pid, timeout \\ 5000) do
    GenServer.call(pid, :len, timeout)
  end

  @doc """
  Returns true if `item` matches some element in the queue, otherwise false.

  `pid` is the process ID of the BlockingQueue server.
  """
  @spec member?(pid, any, integer) :: boolean
  def member?(pid, item, timeout \\ 5000) do
    GenServer.call(pid, {:member, item}, timeout)
  end

  @doc """
  Filters the queue by removing all items for which the function `func` returns false.

  `pid` is the process ID of the BlockingQueue server.
  `func` is the predicate used to filter the queue.
  """
  @spec filter(pid, (any -> boolean), integer) :: nil
  def filter(pid, func, timeout \\ 5000) when is_function(func, 1) do
    GenServer.call(pid, {:filter, func}, timeout)
  end

end
