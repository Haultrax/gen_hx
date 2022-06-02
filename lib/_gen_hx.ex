defmodule GenHx do
  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      use GenServer
      require Logger

      child_spec_opts = Keyword.get(opts, :child_spec_opts, [])

      def child_spec(arg) do
        default = %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [arg]}
        }

        Supervisor.child_spec(default, unquote(child_spec_opts))
      end

      def start_link(opts) do
        try do
          fetch_data()
        rescue
          error ->
            Logger.error(inspect(error))
            Logger.warn("waiting to initialise #{__MODULE__}")
            GenServer.start_link(__MODULE__, nil, name: __MODULE__)
        else
          data -> GenServer.start_link(__MODULE__, data, name: __MODULE__)
        end
      end
    end
  end
end
