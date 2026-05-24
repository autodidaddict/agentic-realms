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
      assert {:error, {:unknown_action_type, "emote"}} =
               Validator.validate([
                 %{
                   "trigger" => "player_entered",
                   "actions" => [%{"type" => "emote", "text" => "smiles"}]
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
      # First behavior is valid; second has unknown trigger. Should report
      # only the unknown trigger.
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
end
