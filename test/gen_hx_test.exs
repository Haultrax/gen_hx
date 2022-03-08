defmodule GenHxTest do
  use ExUnit.Case

  defp get_state(pid) do
    %{accessed: false, data: data, data_status: :hot} = :sys.get_state(pid)
    data
  end

  test "initialises" do
    defmodule TestCache.Inits do
      use GenHx.Cache
      def fetch_data(), do: :fetched
      def broadcast(_), do: nil
    end

    {:ok, pid} = TestCache.Inits.start_link([])

    assert :fetched = get_state(pid)

    assert :fetched = TestCache.Inits.get_all()

    GenServer.stop(pid)
  end

  test "refresh" do
    defmodule TestCache.Refresh do
      use GenHx.Cache, refresh_milliseconds: 1
      def fetch_data(), do: NaiveDateTime.utc_now()
      def broadcast(_), do: nil
    end

    {:ok, pid} = TestCache.Refresh.start_link([])

    t1 = get_state(pid)
    :timer.sleep(1)
    t2 = TestCache.Refresh.get_all()

    GenServer.stop(pid)

    assert NaiveDateTime.diff(t2, t1, :millisecond) > 0
  end

  test "broadcast" do
    defmodule TestCache.Broadcast do
      use GenHx.Cache, refresh_milliseconds: 1
      def fetch_data(), do: :hello

      def broadcast(data) do
        [pid] = Process.info(self())[:dictionary][:"$ancestors"]
        send(pid, data)
      end
    end

    {:ok, pid} = TestCache.Broadcast.start_link([])

    receive do
      :hello -> nil
    end

    assert :hello = TestCache.Broadcast.get_all()

    GenServer.stop(pid)
  end
end
