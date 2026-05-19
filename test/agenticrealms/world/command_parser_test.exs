defmodule AgenticRealms.World.CommandParserTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.CommandParser

  describe "empty / whitespace input" do
    test "empty string" do
      assert {:empty} = CommandParser.parse("")
    end

    test "whitespace only" do
      assert {:empty} = CommandParser.parse("   ")
    end

    test "mixed whitespace only" do
      assert {:empty} = CommandParser.parse("\n\t  ")
    end
  end

  describe "look" do
    test "look" do
      assert {:look} = CommandParser.parse("look")
    end

    test "uppercase + padding" do
      assert {:look} = CommandParser.parse("  LOOK  ")
    end

    test "l alias" do
      assert {:look} = CommandParser.parse("l")
    end

    test "look with trailing text is still :look (object-targeted look out of scope)" do
      assert {:look} = CommandParser.parse("look around")
    end
  end

  describe "inventory" do
    test "inventory" do
      assert {:inventory} = CommandParser.parse("inventory")
    end

    test "inv" do
      assert {:inventory} = CommandParser.parse("inv")
    end

    test "i" do
      assert {:inventory} = CommandParser.parse("i")
    end

    test "uppercase" do
      assert {:inventory} = CommandParser.parse("INV")
    end
  end

  describe "movement (FR-006)" do
    test "north / n" do
      assert {:move, :north} = CommandParser.parse("north")
      assert {:move, :north} = CommandParser.parse("n")
      assert {:move, :north} = CommandParser.parse("N")
      assert {:move, :north} = CommandParser.parse("  north  ")
    end

    test "south / s" do
      assert {:move, :south} = CommandParser.parse("south")
      assert {:move, :south} = CommandParser.parse("s")
    end

    test "east / e" do
      assert {:move, :east} = CommandParser.parse("east")
      assert {:move, :east} = CommandParser.parse("e")
    end

    test "west / w" do
      assert {:move, :west} = CommandParser.parse("west")
      assert {:move, :west} = CommandParser.parse("w")
    end

    test "up / u" do
      assert {:move, :up} = CommandParser.parse("up")
      assert {:move, :up} = CommandParser.parse("u")
    end

    test "down / d" do
      assert {:move, :down} = CommandParser.parse("down")
      assert {:move, :down} = CommandParser.parse("d")
    end

    test "go <direction>" do
      assert {:move, :north} = CommandParser.parse("go north")
      assert {:move, :north} = CommandParser.parse("go  NORTH")
    end

    test "go alone is unknown" do
      assert {:unknown, "go"} = CommandParser.parse("go")
    end

    test "go to a non-direction is unknown" do
      assert {:unknown, "go nowhere"} = CommandParser.parse("go nowhere")
    end
  end

  describe "take" do
    test "take with single-word name" do
      assert {:take, "lantern"} = CommandParser.parse("take lantern")
    end

    test "take with multi-word name" do
      assert {:take, "brass lantern"} = CommandParser.parse("take brass lantern")
    end

    test "normalizes case + collapses internal whitespace" do
      assert {:take, "brass lantern"} = CommandParser.parse("  TAKE   Brass  Lantern  ")
    end

    test "take with no target" do
      assert {:invalid_take_target} = CommandParser.parse("take")
    end

    test "take with only whitespace after verb" do
      assert {:invalid_take_target} = CommandParser.parse("take  ")
    end

    test "get alias" do
      assert {:take, "journal"} = CommandParser.parse("get journal")
    end

    test "pick alias (one-word, accepts awkward `pick up`)" do
      assert {:take, "up journal"} = CommandParser.parse("pick up journal")
    end
  end

  describe "drop" do
    test "drop with name" do
      assert {:drop, "letter"} = CommandParser.parse("drop letter")
    end

    test "drop with no target" do
      assert {:invalid_drop_target} = CommandParser.parse("drop")
    end

    test "put alias" do
      assert {:drop, "letter"} = CommandParser.parse("put letter")
    end
  end

  describe "unknown verbs (FR-018)" do
    test "single unknown verb" do
      assert {:unknown, "dance"} = CommandParser.parse("dance")
    end

    test "phrase" do
      assert {:unknown, "hello world"} = CommandParser.parse("hello world")
    end

    test "unknown is returned in original case" do
      assert {:unknown, "Dance"} = CommandParser.parse("Dance")
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Feature 004 — Communication verbs
  # ──────────────────────────────────────────────────────────────────────

  describe "say (US1)" do
    test "basic say" do
      assert {:say, "hello"} = CommandParser.parse("say hello")
    end

    test "preserves internal whitespace in text" do
      assert {:say, "hi   mom"} = CommandParser.parse("say hi   mom")
    end

    test "preserves case in text" do
      assert {:say, "HEY"} = CommandParser.parse("SAY HEY")
      assert {:say, "Hello World"} = CommandParser.parse("say Hello World")
    end

    test "apostrophe shortcut without space" do
      assert {:say, "hello"} = CommandParser.parse("'hello")
    end

    test "apostrophe shortcut with leading space" do
      assert {:say, "hello"} = CommandParser.parse("' hello")
    end

    test "apostrophe shortcut preserves case" do
      assert {:say, "Hi There"} = CommandParser.parse("'Hi There")
    end

    test "say alone produces :say_empty" do
      assert {:say_empty} = CommandParser.parse("say")
    end

    test "say with whitespace-only text produces :say_empty" do
      assert {:say_empty} = CommandParser.parse("say     ")
    end

    test "apostrophe alone produces :say_empty" do
      assert {:say_empty} = CommandParser.parse("'")
    end

    test "apostrophe with only whitespace produces :say_empty" do
      assert {:say_empty} = CommandParser.parse("'    ")
    end
  end

  describe "emote (US2)" do
    test "emote verb form" do
      assert {:emote, "waves"} = CommandParser.parse("emote waves")
    end

    test "me alias" do
      assert {:emote, "waves"} = CommandParser.parse("me waves")
    end

    test "colon shortcut without space" do
      assert {:emote, "waves"} = CommandParser.parse(":waves")
    end

    test "colon shortcut with leading space" do
      assert {:emote, "waves"} = CommandParser.parse(": waves")
    end

    test "preserves case in text" do
      assert {:emote, "Waves"} = CommandParser.parse("EMOTE Waves")
      assert {:emote, "Bows DEEPLY"} = CommandParser.parse("me Bows DEEPLY")
    end

    test "emote alone produces :emote_empty" do
      assert {:emote_empty} = CommandParser.parse("emote")
    end

    test "me alone produces :emote_empty" do
      assert {:emote_empty} = CommandParser.parse("me")
    end

    test "colon alone produces :emote_empty" do
      assert {:emote_empty} = CommandParser.parse(":")
    end

    test "mention does NOT parse as me ntion" do
      # `me` must match the whole first word, not be a prefix
      assert {:unknown, "mention"} = CommandParser.parse("mention")
    end
  end

  describe "tell (US3)" do
    test "basic tell" do
      assert {:tell, "alice", "hi"} = CommandParser.parse("tell alice hi")
    end

    test "t alias" do
      assert {:tell, "alice", "hi"} = CommandParser.parse("t alice hi")
    end

    test "preserves recipient case and internal whitespace in text" do
      assert {:tell, "Bob", "hi there"} = CommandParser.parse("tell Bob   hi there")
    end

    test "tell alone produces :tell_no_recipient" do
      assert {:tell_no_recipient} = CommandParser.parse("tell")
    end

    test "t alone produces :tell_no_recipient" do
      assert {:tell_no_recipient} = CommandParser.parse("t")
    end

    test "tell with only recipient produces :tell_no_text" do
      assert {:tell_no_text, "alice"} = CommandParser.parse("tell alice")
    end

    test "tell with recipient and whitespace-only text produces :tell_no_text" do
      assert {:tell_no_text, "alice"} = CommandParser.parse("tell alice    ")
    end

    test "tell is NOT accepted as whisper alias" do
      refute match?({:whisper, _, _}, CommandParser.parse("tell alice hi"))
    end
  end

  describe "whisper (US4)" do
    test "basic whisper" do
      assert {:whisper, "alice", "hi"} = CommandParser.parse("whisper alice hi")
    end

    test "preserves recipient case and internal whitespace in text" do
      assert {:whisper, "Bob", "hi there"} = CommandParser.parse("whisper Bob   hi there")
    end

    test "whisper alone produces :whisper_no_recipient" do
      assert {:whisper_no_recipient} = CommandParser.parse("whisper")
    end

    test "whisper with only recipient produces :whisper_no_text" do
      assert {:whisper_no_text, "alice"} = CommandParser.parse("whisper alice")
    end

    test "whisper is NOT accepted as tell alias" do
      refute match?({:tell, _, _}, CommandParser.parse("whisper alice hi"))
    end

    test "w is reserved for the west movement alias from feature 003" do
      # The 004 spec originally listed `w` as a whisper alias, but it conflicts
      # with 003's `w`-for-west. Resolved in favor of the movement alias.
      assert {:move, :west} = CommandParser.parse("w")
    end
  end
end
