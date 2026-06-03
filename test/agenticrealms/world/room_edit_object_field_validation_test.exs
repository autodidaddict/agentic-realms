defmodule AgenticRealms.World.RoomEditObjectFieldValidationTest do
  @moduledoc """
  Aggregate-boundary defense-in-depth for `Room.execute/2` on
  `EditObject`. Addresses bug_010 from the PR #30 review.
  """

  use ExUnit.Case, async: true

  alias AgenticRealms.World.Room
  alias AgenticRealms.World.Commands.EditObject
  alias AgenticRealms.World.Events.{RoomCreated, ObjectSpawned, ObjectEdited}

  @room_id "00000000-0000-0000-0000-0000cccc0001"
  @region_id "00000000-0000-0000-0000-0000cccc0900"
  @object_id "00000000-0000-0000-0000-0000cccc0100"

  defp room_with_object do
    %Room{}
    |> Room.apply(%RoomCreated{
      room_id: @room_id,
      region_id: @region_id,
      name: "Test Chamber",
      description: "A bare test chamber."
    })
    |> Room.apply(%ObjectSpawned{
      object_id: @object_id,
      room_id: @room_id,
      name: "test pot",
      short_description: "a test pot",
      long_description: "A test pot.",
      fixed: false
    })
  end

  test "accepts every key in the editable allowlist" do
    cmd = %EditObject{
      room_id: @room_id,
      object_id: @object_id,
      wizard_id: 1,
      fields_changed: %{
        name: "edited",
        short_description: "edited",
        long_description: "edited",
        fixed: true
      }
    }

    assert %ObjectEdited{} = Room.execute(room_with_object(), cmd)
  end

  test "refuses :room_id as a touched field (would teleport the row)" do
    cmd = %EditObject{
      room_id: @room_id,
      object_id: @object_id,
      wizard_id: 1,
      fields_changed: %{room_id: "some_other_room"}
    }

    assert {:error, :invalid_field} = Room.execute(room_with_object(), cmd)
  end

  test "refuses :player_id as a touched field (would transfer ownership)" do
    cmd = %EditObject{
      room_id: @room_id,
      object_id: @object_id,
      wizard_id: 1,
      fields_changed: %{player_id: 999}
    }

    assert {:error, :invalid_field} = Room.execute(room_with_object(), cmd)
  end

  test "refuses :quest_player_id (would retroactively quest-scope the row)" do
    cmd = %EditObject{
      room_id: @room_id,
      object_id: @object_id,
      wizard_id: 1,
      fields_changed: %{quest_player_id: 1, quest_instance_id: Ecto.UUID.generate()}
    }

    assert {:error, :invalid_field} = Room.execute(room_with_object(), cmd)
  end

  test "refuses :behaviors (out of milestone-1 scope)" do
    cmd = %EditObject{
      room_id: @room_id,
      object_id: @object_id,
      wizard_id: 1,
      fields_changed: %{behaviors: [%{type: "say", text: "hi"}]}
    }

    assert {:error, :invalid_field} = Room.execute(room_with_object(), cmd)
  end

  test "mixed allowed + disallowed keys also refused" do
    cmd = %EditObject{
      room_id: @room_id,
      object_id: @object_id,
      wizard_id: 1,
      fields_changed: %{name: "fine", room_id: "not-fine"}
    }

    assert {:error, :invalid_field} = Room.execute(room_with_object(), cmd)
  end
end
