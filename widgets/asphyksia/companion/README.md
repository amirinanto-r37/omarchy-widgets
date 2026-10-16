# companion

An agent core that is born different every time.

The tile shows what the coding agent is doing: its voice is a polar waveform,
its attention a radar that locks onto the tool in use. Its form, though, comes
from a genome seeded at birth, so no two companions look alike.

## Drive it

```sh
owl-send <this widget file> set detail "reading widget.owl"   # first, so it lands in the log
owl-send <this widget file> set activity bash                 # bash read edit web think error idle
```

## Let it express itself

```sh
owl-send <this widget file> set sigil "vigilante nocturno"    # a name, shown instead of the mode
owl-send <this widget file> set mood wild                     # calm | focused | curious | wild
owl-send <this widget file> set genome 1760312345             # adopt a species
```

`mood` scales the tempo of every animation (0.6x to 1.7x).

## The genome

`genome` is seeded once, at birth, from the second of the first interaction, so
no random command is needed and nothing extra runs. Twelve values are then drawn
with a small linear congruential generator and decide:

- the number of arms and the sides of the outer polygon (3 to 12)
- the satellites, the direction of spin, the twist and the orbit radius
- the tick-ring count, and the companion's own idle colour

An activity overrides the colour with the usual per-tool neon, and the mix of
tools bends the shape over time (bash opens it up, read and web twist it).

## Rarity

Independent rolls, all from the genome except shiny:

| grade | chance | look | badge |
|---|---|---|---|
| ornate | 1/10 | an extra outer ring | `◇` |
| aurora | 1/100 | the shell turns rainbow | `❋` |
| eclipse | 1/1000 | near-black core, bright rim | `◑` |
| shiny | 1/4096 | iridescent corona and sparkles | `✦` |

Shiny derives from the birth time, not from the genome, so it stays with the
companion: adopting someone's species code never brings a shiny along.

## Sharing and growth

The screen shows the species code with a **copy code** button, and an input
adopts a code from another companion. The four evolution stages (spark, sprite,
being, aura) arrive at 30, 120 and 400 interactions and are the same for
everyone; only the form they express is personal.

Requires `procps-ng` (for `pgrep`).
