defmodule AgenticRealmsWeb.GameComponents.LogEntry do
  @moduledoc """
  The narrative log entry renderer. One public `log_entry/1` function
  with a clause per `entry.kind` — room, detail, narrate, speech (and
  its variants), command echo, system, combat, and the private/whisper
  surfaces from feature 004 plus the chat/emote/behavior variants from
  features 009/010/011.

  All `text` and `actor` values originate from player input and are
  rendered through HEEx auto-escaping (the default `{ @entry.text }`
  interpolation) per FR-024.
  """

  use AgenticRealmsWeb, :html

  import AgenticRealmsWeb.GameComponents.Primitives, only: [direction_arrow: 1]

  attr :entry, :map, required: true

  def log_entry(%{entry: %{kind: :room, room: %AgenticRealms.World.RoomView{}}} = assigns) do
    ~H"""
    <div class="log-entry room">
      <div class="room-head">
        <span class="room-name">{@entry.room.name}</span>
      </div>
      <div class="room-body">{@entry.room.description}</div>
      <div :if={@entry.room.exits != []} class="exits">
        <button
          :for={exit <- @entry.room.exits}
          class={["exit-chip", exit.direction == "rift" && "exit-rift"]}
          phx-click="submit_command"
          phx-value-text={exit.direction}
        >
          <span class="arrow">{direction_arrow(exit.direction)}</span>
          <span>{exit.direction} · {exit.target_name}</span>
        </button>
      </div>
      <div :if={@entry.room.objects != [] or @entry.room.other_players != []} class="entities">
        <span :for={{obj, idx} <- Enum.with_index(@entry.room.objects)}>
          <span class="entity item">{obj.name}</span>
          <span :if={idx < length(@entry.room.objects) - 1 or @entry.room.other_players != []}>
            ·
          </span>
        </span>
        <span :for={{p, idx} <- Enum.with_index(@entry.room.other_players)}>
          <span class="entity player-other">{p.name}</span>
          <span :if={idx < length(@entry.room.other_players) - 1}> · </span>
        </span>
      </div>
      <div :if={@entry.room.npcs != []} class="room-section also-here">
        <span class="room-section-label">Also here:</span>
        <span :for={{npc, idx} <- Enum.with_index(@entry.room.npcs)} class="also-here-entry">
          <span class="entity npc">{npc.name}</span><span
            :if={npc.short_description not in [nil, ""]}
            class="also-here-short"
          > — {npc.short_description}</span><span :if={idx < length(@entry.room.npcs) - 1}> · </span>
        </span>
      </div>
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :room}} = assigns) do
    ~H"""
    <div class="log-entry room">
      <div class="room-head">
        <span class="room-name">{@entry.room.name}</span>
        <span>· {String.slice(@entry.room.desc, 0..30)}...</span>
        <span class="room-coord">{@entry.room.coord}</span>
      </div>
      <div class="room-body">{@entry.room.desc}</div>
      <div class="exits">
        <button :for={exit <- @entry.room.exits} class="exit-chip">
          <span class="arrow">{direction_arrow(exit.dir)}</span>
          <span>{exit.dir} · {exit.to}</span>
        </button>
      </div>
      <div class="entities">
        <span :for={{entity, idx} <- Enum.with_index(@entry.room.entities)}>
          <span class={"entity #{entity.type}"}>{entity.name}</span>
          <span :if={idx < length(@entry.room.entities) - 1}> · </span>
        </span>
      </div>
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :detail, target_kind: :object}} = assigns) do
    ~H"""
    <div class="log-entry detail detail-object">
      <div class="detail-head">
        <span class="detail-name">{@entry.name}</span>
      </div>
      <div class="detail-body">{@entry.long_description}</div>
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :detail, target_kind: :player}} = assigns) do
    ~H"""
    <div class="log-entry detail detail-player">
      <div class="detail-body"><span class="detail-name">{@entry.name}</span> is a player.</div>
      <div :if={@entry[:health_tier]} class="detail-condition">{@entry.health_tier}.</div>
      <div :if={@entry[:power_phrase]} class="detail-power">They seem {@entry.power_phrase}.</div>
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :detail, target_kind: :npc}} = assigns) do
    ~H"""
    <div class="log-entry detail detail-npc">
      <div class="detail-head">
        <span class="detail-name">{@entry.name}</span>
      </div>
      <div class="detail-body">{@entry.long_description}</div>
      <div :if={@entry[:health_tier]} class="detail-condition">{@entry.health_tier}.</div>
      <div :if={@entry[:power_phrase]} class="detail-power">
        It seems {@entry.power_phrase}.
      </div>
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :narrate}} = assigns) do
    ~H"""
    <div class="log-entry narrate">{@entry.text}</div>
    """
  end

  def log_entry(%{entry: %{kind: :npc_speech}} = assigns) do
    ~H"""
    <div class="log-entry speech speech-npc">
      <span class="who">{@entry.actor_name}</span> says, &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :room_speech}} = assigns) do
    ~H"""
    <div class="log-entry narrate narrate-room">{@entry.text}</div>
    """
  end

  def log_entry(%{entry: %{kind: :room_emote}} = assigns) do
    ~H"""
    <div class="log-entry ambient ambient-room">{@entry.text}</div>
    """
  end

  def log_entry(%{entry: %{kind: :npc_emote}} = assigns) do
    ~H"""
    <div class="log-entry ambient ambient-npc">
      <span class="who">{@entry.actor_name}</span> {@entry.text}
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :object_emote}} = assigns) do
    ~H"""
    <div class="log-entry ambient ambient-object">
      <span class="who">{@entry.actor_name}</span> {@entry.text}
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :chat_speech}} = assigns) do
    ~H"""
    <div class="log-entry speech speech-npc speech-chat">
      <span class="who">{@entry.actor_name}</span> says, &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :chat_emote}} = assigns) do
    ~H"""
    <div class="log-entry emote emote-chat">
      <span class="who">{@entry.actor_name}</span> {@entry.text}
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :chat_system}} = assigns) do
    variant_class =
      case assigns.entry[:kind_variant] do
        :chat_new -> "chat-new"
        :chat_continuing -> "chat-continuing"
        :chat_fallback -> "chat-fallback"
        :chat_in_flight_rejection -> "chat-in-flight"
        _ -> "chat-other"
      end

    assigns = Phoenix.Component.assign(assigns, :variant_class, variant_class)

    ~H"""
    <div class={"log-entry chat-system " <> @variant_class}>{@entry.text}</div>
    """
  end

  def log_entry(%{entry: %{kind: :cmd}} = assigns) do
    ~H"""
    <div class="log-entry cmd">{@entry.text}</div>
    """
  end

  def log_entry(%{entry: %{kind: :said}} = assigns) do
    ~H"""
    <div class="log-entry said">
      <span class="who">{@entry.who}</span> says, &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :whisper}} = assigns) do
    ~H"""
    <div class="log-entry whisper">{@entry.text}</div>
    """
  end

  def log_entry(%{entry: %{kind: :system}} = assigns) do
    ~H"""
    <div class="log-entry system">{@entry.text}</div>
    """
  end

  def log_entry(%{entry: %{kind: :speech}} = assigns) do
    ~H"""
    <div class="log-entry speech">
      <span class="who">{@entry.actor}</span> says, &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :speech_self}} = assigns) do
    ~H"""
    <div class="log-entry speech speech-self">
      <span class="who">You</span> say, &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :emote_action}} = assigns) do
    ~H"""
    <div class="log-entry emote">
      <span class="who">{@entry.actor}</span> {@entry.text}
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :private_tell_in}} = assigns) do
    ~H"""
    <div class="log-entry private private-tell">
      <em><span class="who">{@entry.actor}</span> tells you,</em> &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :private_tell_out}} = assigns) do
    ~H"""
    <div class="log-entry private private-tell private-self">
      <em>You tell <span class="who">{@entry.recipient}</span>,</em> &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :private_whisper_in}} = assigns) do
    ~H"""
    <div class="log-entry private private-whisper">
      <em><span class="who">{@entry.actor}</span> whispers to you,</em> &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :private_whisper_out}} = assigns) do
    ~H"""
    <div class="log-entry private private-whisper private-self">
      <em>You whisper to <span class="who">{@entry.recipient}</span>,</em> &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :combat}} = assigns) do
    ~H"""
    <div class="log-entry combat">
      <span class="combat-swing">HIT</span>
      <span>{@entry.text}</span>
      <span class="combat-num">−{@entry.dmg}</span>
      <div class="combat-bar">
        <i style={"transform: scaleX(#{@entry.pct})"}></i>
      </div>
    </div>
    """
  end

  def log_entry(assigns) do
    ~H"""
    """
  end
end
