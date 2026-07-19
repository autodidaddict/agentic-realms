# SRD 5e

Pure-Elixir tabletop RPG dice management and rule resolution modeled on the System
Reference Document (SRD) 5.2.

This is early, volatile work. The API is not stable and most of it is not built yet.

## Installation

Add `srd_5e` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:srd_5e, "~> 0.1"}
  ]
end
```

## License

The code is released under the Apache License 2.0. See [LICENSE](LICENSE).

This work includes material from the System Reference Document 5.2 ("SRD 5.2") by
Wizards of the Coast LLC, available at https://www.dndbeyond.com/srd, and material
from the System Reference Document 5.1 ("SRD 5.1") by Wizards of the Coast LLC,
available at https://dnd.wizards.com/resources/systems-reference-document. Both are
licensed under the Creative Commons Attribution 4.0 International License, available
at https://creativecommons.org/licenses/by/4.0/legalcode.

The engine is modeled on SRD 5.2 by default and incorporates specific rules from
SRD 5.1 as explicit opt-ins.

This project is not affiliated with or endorsed by Wizards of the Coast, and uses
no Wizards trademarks or Product Identity.
