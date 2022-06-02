defmodule GenHx.Cache do
  @callback fetch_data() :: data :: term | :reuse_old_data
  @callback broadcast(data :: term) :: :ok | {:error, term()}

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      use GenHx

      @behaviour GenHx.Cache
      @error_timeout 1000

      refresh_milliseconds = Keyword.get(opts, :refresh_milliseconds)
      always_refresh = Keyword.get(opts, :always_refresh, true)

      def init(nil) do
        schedule_refresh(unquote(refresh_milliseconds), nil)
        {:ok, %{data: nil, data_status: :cold, accessed: true}}
      end

      def init(data) do
        schedule_refresh(unquote(refresh_milliseconds), data)
        {:ok, %{data: data, data_status: :hot, accessed: false}}
      end

      if always_refresh do
        def handle_info(:refresh, state), do: do_refresh(state)
      else
        def handle_info(:refresh, state) do
          if state.accessed do
            do_refresh(state)
          else
            %{state | data_status: :cold}
            schedule_refresh(unquote(refresh_milliseconds), state.data)
            {:noreply, state}
          end
        end
      end

      defp do_refresh(state) do
        state = do_fetch_data(state)
        schedule_refresh(unquote(refresh_milliseconds), state.data)
        {:noreply, state}
      end

      defp do_fetch_data(state) do
        case fetch_data() do
          :reuse_old_data ->
            %{state | data_status: :cold}

          data ->
            if Kernel.function_exported?(__MODULE__, :broadcast, 1) do
              apply(__MODULE__, :broadcast, [data])
            end

            %{data: data, data_status: :hot, accessed: false}
        end
      end

      def handle_call({:get, fun}, _from, state) do
        reply = run(fun, [state.data])
        state = %{state | accessed: true}
        {:reply, reply, state}
      end

      def handle_call(:refresh, _from, state) do
        state = do_fetch_data(state)

        case state.data_status do
          :hot -> {:reply, :ok, state}
          :cold -> {:reply, {:error, :reusing_old_data}, state}
        end
      end

      def get_all(timeout \\ 5000), do: get(& &1, timeout)

      def get(selector, timeout \\ 5000)

      def get(fun, timeout) when is_function(fun, 1) do
        GenServer.call(__MODULE__, {:get, fun}, timeout)
      end

      def get(key, timeout) when is_atom(key) do
        get(& &1[key], timeout)
      end

      def refresh(timeout \\ 5000) do
        GenServer.call(__MODULE__, :refresh, timeout)
      end

      defp schedule_refresh(_, nil), do: Process.send_after(__MODULE__, :refresh, @error_timeout)
      defp schedule_refresh(nil, _), do: nil
      defp schedule_refresh(refresh_time, _), do: Process.send_after(__MODULE__, :refresh, refresh_time)

      defp run(_, nil), do: []
      defp run({m, f, a}, extra), do: apply(m, f, extra ++ a)
      defp run(fun, extra), do: apply(fun, extra)

      defoverridable child_spec: 1
      defoverridable start_link: 1
    end
  end
end
