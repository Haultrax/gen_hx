defmodule GenHx.Cache do
  @callback fetch_data() :: data :: term | :reuse_old_data
  @callback broadcast(data :: term) :: :ok | {:error, term()}

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      use GenHx

      @behaviour GenHx.Cache

      refresh_milliseconds = Keyword.get(opts, :refresh_milliseconds)
      always_refresh = Keyword.get(opts, :always_refresh, true)

      def init(data) do
        schedule_refresh(unquote(refresh_milliseconds))
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
            schedule_refresh(unquote(refresh_milliseconds))
            {:noreply, state}
          end
        end
      end

      defp do_refresh(state) do
        state =
          case fetch_data() do
            :reuse_old_data ->
              %{state | data_status: :cold}

            data ->
              if Kernel.function_exported?(__MODULE__, :broadcast, 1) do
                apply(__MODULE__, :broadcast, [data])
              end

              %{data: data, data_status: :hot, accessed: false}
          end

        schedule_refresh(unquote(refresh_milliseconds))
        {:noreply, state}
      end

      def handle_call({:get, fun}, _from, state) do
        reply = run(fun, [state.data])
        state = %{state | accessed: true}
        {:reply, reply, state}
      end

      def get_all(timeout \\ 5000), do: get(& &1, timeout)

      def get(selector, timeout \\ 5000)

      def get(fun, timeout) when is_function(fun, 1) do
        GenServer.call(__MODULE__, {:get, fun}, timeout)
      end

      def get(key, timeout) when is_atom(key) do
        get(& &1[key], timeout)
      end

      defp schedule_refresh(nil), do: nil
      defp schedule_refresh(refresh_time), do: Process.send_after(self(), :refresh, refresh_time)

      defp run({m, f, a}, extra), do: apply(m, f, extra ++ a)
      defp run(fun, extra), do: apply(fun, extra)

      defoverridable child_spec: 1
      defoverridable start_link: 1
    end
  end
end
