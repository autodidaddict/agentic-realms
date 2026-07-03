defmodule AgenticRealms.NpcMinds.ConfigTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.NpcMinds.Config

  test "workflow_id/1 prefixes with npc-" do
    assert Config.workflow_id("abc-123") == "npc-abc-123"
  end

  test "entity_id_from_workflow_id/1 strips the prefix; nil for non-NPC ids" do
    assert Config.entity_id_from_workflow_id("npc-abc-123") == "abc-123"
    assert Config.entity_id_from_workflow_id("other-1") == nil
  end

  test "reads the agreed contract values from test config" do
    assert Config.temporal_task_queue() == "npc-minds"
    assert Config.workflow_type() == "NpcWorkflow"
    assert Config.temporal_namespace() == "default"
    assert Config.service_secret() == "test-npc-secret"
    assert is_integer(Config.reconcile_interval_ms())
  end
end
