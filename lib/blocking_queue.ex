defmodule BlockingQueue do
  use GenServer

  # Can I get this from somewhere?
  @type on_start :: {:ok, pid} | :ignore | {:error, {:already_started, pid} | term}

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

  def handle_call({:push, item}, waiter, {max, list}) when length(list) > max do
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

  @spec push(pid, any) :: nil
  def push(pid, item), do: GenServer.call(pid, {:push, item})

  @spec pop(pid) :: any
  def pop(pid), do: GenServer.call(pid, :pop)
end
