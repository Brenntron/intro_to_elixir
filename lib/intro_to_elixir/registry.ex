defmodule ITE.Registry do
  use GenServer

  ## Client API

  @doc """
  Starts the registry.
  """
  def start_link(event_manager, buckets, opts \\ []) do
    GenServer.start_link(__MODULE__, {event_manager, buckets}, opts)
  end

  @doc """
  Looks up the bucket pid for 'name' stored in 'server'.

  Returns '{:ok, pid}' if the bucket exists, ':error' otherewise.
  """
  def lookup(server, name) do
    GenServer.call(server, {:lookup, name})
  end

  @doc """
  Ensures there is a bucket associated to the given 'name' in 'server'.
  """
  def create(server, name) do
    GenServer.cast(server, {:create, name})
  end

  def stop(server) do
    GenServer.call(server, :stop)
  end

  ## Server Callbacks

  def init({events, buckets}) do
    names = HashDict.new
    refs  = HashDict.new
    {:ok, %{names: names, refs: refs, events: events, buckets: buckets}}
  end

  def handle_call({:lookup, name}, _from, state) do
    {:reply, HashDict.fetch(state.names, name), state}
  end

  def handle_cast({:create, name}, state) do
    if HashDict.get(state.names, name) do
      {:norely, state}
    else
      {:ok, pid} = ITE.Bucket.Supervisor.start_bucket(state.buckets)
      ref   = Process.monitor(pid)
      refs  = HashDict.put(state.refs, ref, name)
      names = HashDict.put(state.names, name, pid)
      GenEvent.sync_notify(state.events, {:create, name, pid})
      {:noreply, %{state | names: names, refs: refs}}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    {name, refs} = HashDict.pop(state.refs, ref)
    names = HashDict.delete(state.names, name)
    GenEvent.sync_notify(state.events, {:exit, name, pid})
    {:noreply, %{state | names: names, refs: refs}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
