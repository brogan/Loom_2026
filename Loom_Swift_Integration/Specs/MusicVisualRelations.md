# Music-Visual Relations — Design Principles

**Status**: Conceptual framework / design guide  
**Applies to**: LoomLive performance system, Loom context authoring, MIDI mapping design

This document is not a feature spec. It is a design guide for thinking about the
relationship between musical and visual material — a vocabulary for the creative decisions
the collaborator makes. The software should be designed to support the full range of
relationships described here, not to enforce or suggest any particular one.

**A prior clarification**: the word "collaborator" should not imply a one-way relationship
where the visual responds to the musical. Both parties are responding to each other. The
musician reads the visual collaborator's context switches and gestures as compositional
signals and responds to them musically. The visual collaborator reads the music and responds
visually. This is a dialogue, not a call-and-response where one party calls. The session
and workflow architecture for supporting this bidirectional dialogue is in `SessionWorkflow.md`.

---

## 1. Types of Association

The fundamental distinction is between **tight** and **loose** coupling — but this is a
spectrum, not a binary, and the most interesting creative territory lies in the ability to
move along that spectrum during performance.

### 1.1 Synchronous (beat-level coupling)

Every musical event has a near-simultaneous visual correspondent. The visual tracks the
music event-by-event: subdivision geometry pulses on the beat, line ratios shift with each
chord change, rendering parameters respond to note velocity in real-time.

This is dramatically immediate and immediately comprehensible. It is also the most exhaustible
form of association — once established, it has said everything it can say. It risks making the
visual layer a mere decoration of the music: a "light organ" with geometric fidelity.

**When it opens up creative space**: Synchronous coupling is most powerful when it is *not
constant* — when it appears after a period of divergence, or when it is deliberately broken.
The moment of tight sync, arrived at from a looser relationship, has compositional force.

### 1.2 Phase-level coupling (section coupling)

Visual changes happen at musical section boundaries rather than event boundaries. The visual
form corresponds to a *musical period* (a phrase, a section, a development) rather than to
individual events. A new context is prepared for the B section; the climax triggers a context
switch to the densest visual material; the resolution returns to the opening forms.

This is the most compositionally robust form of association for extended works. It gives the
visual layer its own internal coherence — a context has room to develop, breathe, and resolve
within itself — while remaining structurally related to the musical form.

### 1.3 Structural analogy

A relationship between *types* of musical structure and *types* of visual structure — not
between specific events but between structural dimensions. This is discussed in detail in
Section 2.

### 1.4 Atmospheric / emotional

The visual forms share an *emotional register* or *quality* with the music without any specific
structural correspondence. Both forms are "dense and turbulent", both are "sparse and
suspended", both are "rapid and brittle" — not because the same parameter is driving both but
because the collaborator has prepared visual material of that character and chosen to deploy
it when the music has that quality.

This is the most immediately accessible form of association for an audience and the most
resistant to mechanical implementation. It cannot be automated; it requires the collaborator
to have a sense of visual character that is sophisticated enough to match musical character
at the level of quality, not just structure.

### 1.5 Contrapuntal / divergent

Music and visuals *pull apart*. The visual form has a character that contrasts with or
contradicts the musical character. Violent rhythmic density in the music; extreme stillness
in the visuals. A lyrical melodic line; harsh, fragmented geometry.

This is the most compositionally demanding form of association because it requires confidence
in the divergence — the audience must be held by the tension between the two forms, not
confused by the apparent mismatch. When it works, it makes both the music and the visuals
more acute than either would be in isolation. The divergence creates a meaning that neither
voice carries alone.

### 1.6 Shifting emphasis

The relationship is not constant. Sometimes the visual leads — the music is accompaniment to
the visual composition. Sometimes the music leads — the visual is responsive. Sometimes neither
leads and both coexist as equal voices. The shift in emphasis is itself a compositional act.

This requires the performance system to support deliberate *de-coupling* as well as coupling.
A "sensitivity" control that the collaborator can lower to near-zero (the visuals proceed
autonomously, no longer responsive to MIDI) and raise (the visuals return to musical contact)
is the simplest implementation.

---

## 2. Structural Analogies — A Framework

These are not natural or inevitable correspondences. They are *available* structural analogies
that the collaborator may choose to employ, modify, invert, or ignore. The value of naming
them is not to prescribe but to make them available as conscious choices.

### 2.1 Intervals and geometric proportions

Musical intervals are ratio relationships between frequencies. A perfect fifth is 3:2. An
octave is 2:1. A major third is 5:4. These same ratios appear in geometric proportions —
in subdivision line ratios, in inset scales, in polygon aspect ratios.

**The analogy**: A subdivision with a 3:2 line ratio (0.6/0.4 split) is geometrically
proportioned like a perfect fifth. A 2:1 split (0.67/0.33, closer to the octave) produces
a different visual character. A subdivision set designed for music in fifths (open, strong,
stable) might use 3:2 proportions throughout. One designed for chromatic, dissonant music
might use irrational proportions (close to √2:1, which has no simple rational expression).

**What this enables**: The collaborator can *compose* a vocabulary of geometric forms whose
proportions are structurally related to the harmonic language of the music. This is not a
mechanical mapping — it is a thematic choice that gives the visual material an internal
coherence that corresponds to the musical language.

### 2.2 Harmonic density and visual complexity

Monophonic (single line), dyadic (two voices), chordal (three or more simultaneous pitches):
this represents increasing harmonic density. The visual analog is subdivision depth:
unsubdivided geometry, one generation, multiple generations.

But the analogy also operates at the level of *type*: a single sustained note has a different
density quality than a rapid melody, even if both are monophonic. The visual analog is the
*motion density* of the current context — how much change is happening in how short a time.

**What this enables**: A context prepared for dense, polyphonic musical material would have
deep subdivision, high PTW activity, complex rendering — not because polyphony mechanically
triggers these but because the collaborator has designed visual material of comparable density.

### 2.3 Interval quality and geometric character

Consonant intervals (octave, fifth, fourth) are stable, clear, resolved. Dissonant intervals
(major seventh, minor second, tritone) are tense, unstable, searching. This quality exists
in geometry too: symmetric, regular forms have a visual consonance; irregular, asymmetric,
fragmented forms have a visual dissonance.

In Loom's terms:
- Visual consonance: equal line ratios (0.5/0.5), low ranDiv jitter, regular subdivision, symmetric inset
- Visual dissonance: unequal line ratios, high ranDiv, asymmetric PTW, broken curvature

**The analogy is not automatic**: a tritone in the music does not require fragmented geometry.
But the collaborator can *choose* to work with this correspondence when the music's harmonic
tension and the visual dissonance reinforce each other — and to *work against* it when the
contrast between musical tension and visual serenity is the more interesting choice.

### 2.4 Melodic movement and visual trajectory

A melody has a trajectory through pitch space: it ascends, descends, leaps, steps, circles,
arrives, departs. These are not just pitches but qualities of motion. The visual analog is
the trajectory of visual change over time — how forms grow, contract, rotate, translate,
emerge, and dissolve.

- A sustained note (melodic stasis) → visual material that develops very slowly or not at all
- A rising phrase → forms that expand, rise, or increase in complexity
- A falling phrase → contraction, descent, simplification
- A melodic leap → an abrupt visual discontinuity (context switch, scale jump)
- A repeated figure (ostinato) → a looping visual pattern
- A developing motif → a visual form undergoing progressive transformation

**Important**: this analogy operates at the level of *quality of motion*, not direction.
"Rising" in visual terms might mean many things — literal upward translation, increasing
visual weight, expanding inset scale, brightening palette. The collaborator chooses which
visual dimension corresponds to melodic ascent for this piece.

### 2.5 Harmonic movement and visual transition quality

A chord progression moves from one harmonic context to another. The *quality* of that movement
matters: smooth voice-leading (common tones, minimal motion) vs. abrupt harmonic shift;
diatonic motion (moving within a key) vs. chromatic motion (moving outside it).

The visual analog is the *quality of transition* between contexts:
- Smooth voice-leading → crossfade, morphing, gradual parameter change
- Abrupt harmonic shift → cut, instantaneous context switch
- Diatonic → the new context shares visual DNA with the previous (same geometry, different rendering)
- Chromatic → the new context is a genuine departure (different geometry, different character)

**What this enables**: The collaborator can design not just the contexts but the transitions
between them — a vocabulary of transition types that corresponds to the harmonic vocabulary
of the music. A piece that modulates suddenly and distantly would have cuts; one that
voice-leads smoothly would have crossfades.

### 2.6 Register and visual scale/weight

High register: delicacy, lightness, rapid motion, smaller intervals. Low register: weight,
slowness, mass, larger intervals.

Visual analogs:
- High register → small inset scales, fine subdivision detail, fast oscillator rates, thin rendering
- Low register → large forms, slower evolution, heavier strokes, wider spacing
- Middle register → the visual "ground" that persists while high and low register engage

This is one of the most immediate and accessible structural analogies — audiences feel the
correspondence between musical register and visual weight/scale without needing to be told
about it. It can be used directly (reinforcing) or inverted (high register → heavy visual
forms creates a productive disorientation).

---

## 3. Dimensions of the Relationship

Beyond the type of association, the relationship between music and visuals has several
dimensions that change independently over the course of a performance.

### 3.1 Tightness

How closely does the visual respond to musical events? From synchronous (every beat) to
section-level to fully autonomous. This is a continuous parameter, not a mode switch.
The collaborator controls tightness via the sensitivity control and via their own choices
about when to switch contexts.

### 3.2 Direction of influence

Who is leading? Most of the time in a live performance, the musician sets the pace and the
collaborator responds. But there are moments when the visual leads — the collaborator
makes a dramatic context switch and the musician responds to it — and moments when both
act simultaneously and neither is following.

The software cannot enforce or detect this, but it can support it by making the collaborator's
actions *legible to the musician* — a visual cue that says "I just made a deliberate choice"
rather than "the MIDI triggered this automatically".

### 3.3 Scope

The correspondence can operate at different structural scales simultaneously:
- At the beat level: visual pulse in sync with musical pulse
- At the phrase level: visual phrases that correspond to musical phrases
- At the section level: visual contexts that correspond to musical sections
- At the whole-work level: an overall arc of visual development that mirrors the musical arc

A sophisticated performance has coherence at multiple scales. The visual material is prepared
with this in mind — the beat-level behaviour is consistent with the phrase-level character,
which is consistent with the section-level context, which is consistent with the overall arc.

### 3.4 Explicitness

Some associations are explicit and audible/visible to any attentive observer. Others are
structural correspondences that operate below the level of immediate perception but give the
work a felt coherence. The choice of how explicit to make the associations is a compositional
decision. Fully explicit associations (the beat pulses the geometry) are easy to perceive but
reductive. Fully implicit associations (the proportions correspond to the harmonic series)
may not be consciously perceived but contribute to a sense of *rightness* that the audience
feels without being able to name.

---

## 4. What "Opens Up the Richest Creative Options"

The design principle stated in the initial concept: not "what naturally goes with what" but
"what opens up the richest creative options." Some observations on what this means in practice.

**Natural or expected associations close down possibility.** Once the audience has registered
"beat → pulse", that is the only thing they hear when they hear the beat and see the pulse.
The correspondence has been established and is now consuming interpretive attention. A less
expected association — the harmonic density drives the subdivision but the beat has no visual
correspondent at all — creates a richer interpretive space because the audience is actively
searching for the relationship.

**Productive tension is richer than comfortable correspondence.** A visual-musical relationship
that is slightly off — where the visual is almost but not quite following the music, or where
it follows one musical dimension while ignoring another — creates productive uncertainty. The
audience is uncertain about whether the relationship is intentional, and that uncertainty keeps
them actively engaged.

**The absence of association is also a compositional choice.** Moments where music and visuals
proceed entirely independently — each following its own internal logic — can be the most
powerful in a performance, if they are arrived at from a position of established relationship.
The audience carries the association into the independent section and reads the divergence
against it.

**The relationship itself is the content.** The most interesting performances are not ones
where the visual "illustrates" the music (even beautifully) but ones where the relationship
between music and visuals is the subject of the work — where the audience is listening to and
watching the conversation between two voices, not watching a decorated sound.

---

## 5. Implications for the Software

These principles have consequences for how the performance system should be designed.

**No default mappings.** The software should not ship with pre-wired MIDI-to-visual
associations. Every association is a deliberate compositional choice. The MIDI mapping
panel should be empty until the collaborator fills it.

**The sensitivity control matters.** The ability to reduce the tightness of musical coupling
continuously and in real-time is a core performance capability, not an edge case. It should
be a prominent, accessible control — perhaps the most prominent control in the performance
interface.

**Contexts should have intrinsic character.** The richness of the associations depends on the
collaborator having prepared contexts with genuine visual character that can enter into meaningful
relationships with musical character. The studio interface (Loom) should support developing that
character — the subjective qualities of visual forms, not just their parameter values.

**Transitions are as important as states.** The vocabulary of transitions (cut, crossfade, morph,
extend) is as compositionally significant as the vocabulary of contexts. The performance interface
should make transition choice as deliberate and expressive as context choice.

**Record everything, prescribe nothing.** The performance system should record all collaborator
actions precisely without prescribing what those actions should be. The recording becomes the
score. But during performance, the collaborator should never be constrained by what was planned.
