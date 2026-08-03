defmodule AgenticRealms.World.Transient.EventStoreStub do
  @moduledoc """
  Test double for the transient-purge event-store seam
  (`config :agenticrealms, :transient_event_store`). The in-memory Commanded
  adapter used in `:test` has no `delete_stream`, so the real hard-delete path
  cannot run there; this records the stream/snapshot deletions Purge requests
  in an ETS table so tests can assert which were targeted. Returns `:ok` so the
  read-model row deletes (against the Postgres test DB) still run and are
  asserted.
  """

  @table :transient_event_store_stub

  @doc "Clear recorded deletions (call in test setup)."
  def reset do
    ensure()
    :ets.delete_all_objects(@table)
    :ok
  end

  def delete_stream(stream_uuid, _expected_version, :hard) do
    ensure()
    :ets.insert(@table, {:stream, stream_uuid})
    :ok
  end

  def delete_snapshot(source_uuid) do
    ensure()
    :ets.insert(@table, {:snapshot, source_uuid})
    :ok
  end

  @doc "Stream UUIDs hard-deleted since the last reset."
  def deleted_streams do
    ensure()
    :ets.lookup(@table, :stream) |> Enum.map(&elem(&1, 1))
  end

  @doc "Snapshot source UUIDs deleted since the last reset."
  def deleted_snapshots do
    ensure()
    :ets.lookup(@table, :snapshot) |> Enum.map(&elem(&1, 1))
  end

  defp ensure do
    if :ets.whereis(@table) == :undefined do
      try do
        :ets.new(@table, [:named_table, :public, :bag])
      rescue
        ArgumentError -> @table
      end
    end

    @table
  end
end
