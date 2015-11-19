defimpl Collectable, for: BlockingQueue do
  def into(%BlockingQueue{pid: pid}), do: {nil, &into(pid, &1, &2) }

  defp into(pid, _, {:cont, item}), do: BlockingQueue.push(pid, item)
  defp into(pid, _, :done), do: %BlockingQueue{pid: pid}
  defp into(_, _, :halt), do: :ok
end
