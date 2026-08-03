defmodule AgenticRealms.World.IntentResolver.SystemPrompt do
  @moduledoc """
  Compile-loads the natural-language intent-resolver system prompt from
  `priv/intent_resolver/system_prompt.md`.

  The content is read at compile time via `@external_resource` so it ships
  with the release; editing the markdown file requires a recompile to take
  effect.
  """

  @prompt_path Path.join([:code.priv_dir(:agenticrealms), "intent_resolver", "system_prompt.md"])
  @external_resource @prompt_path
  @prompt_text File.read!(@prompt_path)

  @doc "The system prompt text shipped to the Anthropic Messages API."
  @spec text() :: String.t()
  def text, do: @prompt_text
end
