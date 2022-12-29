defmodule ExUnit.Cluster.Manager do
  @moduledoc false

  use GenServer

  # @typep t :: %__MODULE__{
  #         prefix: atom(),
  #         nodes: map(),
  #         cookie: String.t()
  #       }

  @enforce_keys [:prefix, :nodes, :cookie]
  defstruct @enforce_keys

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec spawn_node(pid()) :: node()
  def spawn_node(pid), do: GenServer.call(pid, :spawn_node)

  @spec get_nodes(pid()) :: list(node())
  def get_nodes(pid), do: GenServer.call(pid, :get_nodes)

  @spec call(pid(), node(), module(), atom(), list(term())) :: term()
  def call(pid, node, module, function, args),
    do: GenServer.call(pid, {:call, node, module, function, args})

  @impl true
  def init(opts) do
    test_module = opts[:test_module]
    test_name = opts[:test_name]

    prefix =
      "#{Atom.to_string(test_module)} #{Atom.to_string(test_name)}"
      |> String.replace([".", " "], "_")
      |> String.to_atom()

    cookie = Base.url_encode64(:crypto.strong_rand_bytes(40))

    state = %__MODULE__{
      prefix: prefix,
      nodes: Map.new(),
      cookie: cookie
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_nodes, _from, state) do
    nodes = Map.keys(state.nodes)
    {:reply, nodes, state}
  end

  @impl true
  def handle_call(:spawn_node, _from, state) do
    name = :peer.random_name(:"#{state.prefix}")

    {:ok, pid, node} =
      :peer.start_link(%{
        name: name,
        host: '127.0.0.1',
        longnames: true,
        connection: :standard_io,
        args: [
          '-loader inet',
          '-hosts 127.0.0.1',
          '-setcookie #{state.cookie}'
          # '-connect_all false'
        ]
      })

    :peer.call(pid, :code, :add_paths, [:code.get_path()])

    for {app, _, _} <- Application.loaded_applications() do
      for {key, val} <- Application.get_all_env(app) do
        :peer.call(pid, Application, :put_env, [app, key, val])
      end
    end

    for node_pid <- Map.values(state.nodes) do
      :peer.call(node_pid, Node, :connect, [node])
    end

    state = %__MODULE__{state | nodes: Map.put(state.nodes, node, pid)}

    {:reply, node, state}
  end

  def handle_call({:call, node, module, function, args}, _from, state) do
    pid = Map.get(state.nodes, node)
    res = :peer.call(pid, module, function, args)
    {:reply, res, state}
  end
end
