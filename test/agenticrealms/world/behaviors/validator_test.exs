defmodule AgenticRealms.World.Behaviors.ValidatorTest do
  @moduledoc """
  Unit tests for the behavior list validator (feature 009).
  See `specs/009-npc-behaviors/contracts/validator.md`.
  """

  use ExUnit.Case, async: true

  alias AgenticRealms.World.Behaviors.Validator

  describe "validate/1" do
    test "empty list is valid" do
      assert :ok = Validator.validate([])
    end

    test "single well-formed behavior is valid" do
      assert :ok =
               Validator.validate([
                 %{
                   "trigger" => "player_entered",
                   "actions" => [%{"type" => "say", "text" => "Hello"}]
                 }
               ])
    end

    test "multi-behavior + multi-action list is valid" do
      assert :ok =
               Validator.validate([
                 %{
                   "trigger" => "player_entered",
                   "actions" => [
                     %{"type" => "say", "text" => "One"},
                     %{"type" => "say", "text" => "Two"}
                   ]
                 },
                 %{
                   "trigger" => "player_left",
                   "actions" => [%{"type" => "say", "text" => "Goodbye"}]
                 }
               ])
    end

    test "non-list input is rejected" do
      assert {:error, :not_a_list} = Validator.validate(%{})
      assert {:error, :not_a_list} = Validator.validate("nope")
      assert {:error, :not_a_list} = Validator.validate(nil)
    end

    test "unknown trigger is rejected" do
      assert {:error, {:unknown_trigger, "on_attack"}} =
               Validator.validate([
                 %{
                   "trigger" => "on_attack",
                   "actions" => [%{"type" => "say", "text" => "x"}]
                 }
               ])
    end

    test "behavior missing 'trigger' key is rejected" do
      assert {:error, :invalid_behavior_shape} =
               Validator.validate([%{"actions" => [%{"type" => "say", "text" => "x"}]}])
    end

    test "behavior with non-list actions is rejected" do
      assert {:error, :actions_not_a_list} =
               Validator.validate([
                 %{"trigger" => "player_entered", "actions" => "say"}
               ])
    end

    test "empty actions list is rejected" do
      assert {:error, :empty_actions} =
               Validator.validate([%{"trigger" => "player_entered", "actions" => []}])
    end

    test "action without 'type' key is rejected" do
      assert {:error, :invalid_action_shape} =
               Validator.validate([
                 %{"trigger" => "player_entered", "actions" => [%{"text" => "x"}]}
               ])
    end

    test "unknown action type is rejected" do
      assert {:error, {:unknown_action_type, "teleport"}} =
               Validator.validate([
                 %{
                   "trigger" => "player_entered",
                   "actions" => [%{"type" => "teleport", "text" => "x"}]
                 }
               ])
    end

    test "say action missing 'text' is rejected" do
      assert {:error, :missing_say_text} =
               Validator.validate([
                 %{"trigger" => "player_entered", "actions" => [%{"type" => "say"}]}
               ])
    end

    test "say action with non-string text is rejected" do
      assert {:error, :missing_say_text} =
               Validator.validate([
                 %{
                   "trigger" => "player_entered",
                   "actions" => [%{"type" => "say", "text" => 42}]
                 }
               ])
    end

    test "say action with empty text is rejected" do
      assert {:error, :empty_say_text} =
               Validator.validate([
                 %{
                   "trigger" => "player_entered",
                   "actions" => [%{"type" => "say", "text" => ""}]
                 }
               ])
    end

    test "say action with text >500 chars is rejected" do
      long = String.duplicate("x", 501)

      assert {:error, :text_too_long} =
               Validator.validate([
                 %{
                   "trigger" => "player_entered",
                   "actions" => [%{"type" => "say", "text" => long}]
                 }
               ])
    end

    test "say action with text exactly 500 chars is accepted" do
      exact = String.duplicate("x", 500)

      assert :ok =
               Validator.validate([
                 %{
                   "trigger" => "player_entered",
                   "actions" => [%{"type" => "say", "text" => exact}]
                 }
               ])
    end

    test "fails fast on first invalid entry" do
      assert {:error, {:unknown_trigger, "bogus"}} =
               Validator.validate([
                 %{
                   "trigger" => "player_entered",
                   "actions" => [%{"type" => "say", "text" => "Hi"}]
                 },
                 %{
                   "trigger" => "bogus",
                   "actions" => [%{"type" => "say", "text" => "x"}]
                 }
               ])
    end
  end

  describe "tick trigger validation (feature 011)" do
    defp say_action, do: %{"type" => "say", "text" => "tick"}

    setup do
      original = Application.get_env(:agenticrealms, AgenticRealms.World.Ticks, [])

      on_exit(fn ->
        Application.put_env(:agenticrealms, AgenticRealms.World.Ticks, original)
      end)

      :ok
    end

    defp put_base_rate(ms) do
      original = Application.get_env(:agenticrealms, AgenticRealms.World.Ticks, [])

      Application.put_env(
        :agenticrealms,
        AgenticRealms.World.Ticks,
        Keyword.put(original, :base_tick_rate_ms, ms)
      )
    end

    test "accepts a tick behavior with a valid interval_ms (multiple of base)" do
      put_base_rate(1_000)

      assert :ok =
               Validator.validate([
                 %{
                   "trigger" => "tick",
                   "interval_ms" => 1_000,
                   "actions" => [say_action()]
                 }
               ])

      assert :ok =
               Validator.validate([
                 %{
                   "trigger" => "tick",
                   "interval_ms" => 5_000,
                   "actions" => [say_action()]
                 }
               ])
    end

    test "rejects a tick behavior with missing interval_ms" do
      put_base_rate(1_000)

      assert {:error, {:invalid_tick_interval, %{reason: :missing}}} =
               Validator.validate([
                 %{
                   "trigger" => "tick",
                   "actions" => [say_action()]
                 }
               ])
    end

    test "rejects a tick behavior with nil interval_ms" do
      put_base_rate(1_000)

      assert {:error, {:invalid_tick_interval, %{reason: :missing}}} =
               Validator.validate([
                 %{
                   "trigger" => "tick",
                   "interval_ms" => nil,
                   "actions" => [say_action()]
                 }
               ])
    end

    test "rejects a tick behavior with string interval_ms" do
      put_base_rate(1_000)

      assert {:error, {:invalid_tick_interval, %{reason: :non_integer, value: "1000"}}} =
               Validator.validate([
                 %{
                   "trigger" => "tick",
                   "interval_ms" => "1000",
                   "actions" => [say_action()]
                 }
               ])
    end

    test "rejects a tick behavior with float interval_ms" do
      put_base_rate(1_000)

      assert {:error, {:invalid_tick_interval, %{reason: :non_integer, value: 1000.0}}} =
               Validator.validate([
                 %{
                   "trigger" => "tick",
                   "interval_ms" => 1000.0,
                   "actions" => [say_action()]
                 }
               ])
    end

    test "rejects a tick behavior with zero interval_ms" do
      put_base_rate(1_000)

      assert {:error, {:invalid_tick_interval, %{reason: :non_positive, value: 0}}} =
               Validator.validate([
                 %{
                   "trigger" => "tick",
                   "interval_ms" => 0,
                   "actions" => [say_action()]
                 }
               ])
    end

    test "rejects a tick behavior with negative interval_ms" do
      put_base_rate(1_000)

      assert {:error, {:invalid_tick_interval, %{reason: :non_positive, value: -500}}} =
               Validator.validate([
                 %{
                   "trigger" => "tick",
                   "interval_ms" => -500,
                   "actions" => [say_action()]
                 }
               ])
    end

    test "rejects a tick behavior whose interval is not a multiple of the base rate" do
      put_base_rate(1_000)

      assert {:error,
              {:invalid_tick_interval, %{reason: :non_multiple, value: 750, base_rate: 1000}}} =
               Validator.validate([
                 %{
                   "trigger" => "tick",
                   "interval_ms" => 750,
                   "actions" => [say_action()]
                 }
               ])
    end

    test "base-rate sensitivity: 1000ms is rejected when base is 100ms, accepted when base is 250ms" do
      put_base_rate(250)

      assert :ok =
               Validator.validate([
                 %{
                   "trigger" => "tick",
                   "interval_ms" => 1_000,
                   "actions" => [say_action()]
                 }
               ])

      put_base_rate(100)

      assert :ok =
               Validator.validate([
                 %{
                   "trigger" => "tick",
                   "interval_ms" => 1_000,
                   "actions" => [say_action()]
                 }
               ])

      put_base_rate(250)

      assert {:error, {:invalid_tick_interval, %{reason: :non_multiple, value: 100}}} =
               Validator.validate([
                 %{
                   "trigger" => "tick",
                   "interval_ms" => 100,
                   "actions" => [say_action()]
                 }
               ])
    end

    test "accepts an emote action in a tick behavior" do
      put_base_rate(1_000)

      assert :ok =
               Validator.validate([
                 %{
                   "trigger" => "tick",
                   "interval_ms" => 1_000,
                   "actions" => [%{"type" => "emote", "text" => "flickers softly."}]
                 }
               ])
    end

    test "rejects an emote action with missing text" do
      put_base_rate(1_000)

      assert {:error, :missing_emote_text} =
               Validator.validate([
                 %{
                   "trigger" => "tick",
                   "interval_ms" => 1_000,
                   "actions" => [%{"type" => "emote"}]
                 }
               ])
    end

    test "rejects an emote action with empty text" do
      put_base_rate(1_000)

      assert {:error, :empty_emote_text} =
               Validator.validate([
                 %{
                   "trigger" => "tick",
                   "interval_ms" => 1_000,
                   "actions" => [%{"type" => "emote", "text" => ""}]
                 }
               ])
    end

    test "rejects an emote action with text > 500 chars" do
      put_base_rate(1_000)
      long = String.duplicate("x", 501)

      assert {:error, :emote_text_too_long} =
               Validator.validate([
                 %{
                   "trigger" => "tick",
                   "interval_ms" => 1_000,
                   "actions" => [%{"type" => "emote", "text" => long}]
                 }
               ])
    end

    test "interval_ms validation does NOT apply to non-tick triggers" do
      put_base_rate(1_000)

      assert :ok =
               Validator.validate([
                 %{
                   "trigger" => "player_entered",
                   "interval_ms" => "not-an-integer",
                   "actions" => [say_action()]
                 }
               ])
    end
  end
end
