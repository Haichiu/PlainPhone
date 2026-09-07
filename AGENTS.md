# PlainPhone Agent Instructions

## Product

PlainPhone is a native iOS product exploring a calmer, minimal, text-first way to
access frequently used apps and actions.

The current implementation is a private, offline, subscription-free iOS 18
SwiftUI app with WidgetKit launchers. Treat it as the current validated baseline,
not as proof that the present feature set or product direction is final.

`SPEC.md` defines the requirements of the current implementation.
It is authoritative when maintaining or verifying that implementation, but it
must not constrain product research or future product strategy unless the Owner
explicitly says so.

## Product principles

PlainPhone should first become a product the Owner genuinely prefers to use in
daily life. Do not optimize for conventional product expectations, feature
completeness, or marketability at the expense of that goal.

Preserve these principles unless evidence supports changing them:

- low interaction cost
- calm and visually minimal
- useful in repeated everyday use
- privacy-respecting
- reliable and understandable
- native-feeling on iOS
- minimal unnecessary configuration, dependencies, and complexity
- fewer, better-considered capabilities rather than feature accumulation

Prefer removing friction over adding capability.

Do not add something merely because it is technically possible or common in
competing products. A meaningful addition should solve a concrete recurring
problem strongly enough to justify its interaction, conceptual, and maintenance
cost.

When completeness conflicts with simplicity, investigate whether the simpler
product is actually better before assuming the missing capability should be added.

## Working modes

Infer the mode from the Owner's task.

### Product research / strategy

Do not modify the implementation unless explicitly asked.

Start by understanding the existing product and its assumptions, then investigate
the problem space rather than merely proposing extensions to the current app.

Distinguish clearly between:
- observed facts and evidence
- assumptions or hypotheses
- interpretation
- recommendations

Actively consider alternatives to the current direction, including simplifying,
changing, postponing, or not building something.

Evaluate ideas by expected user value, frequency of use, interaction cost,
platform constraints, implementation/maintenance cost, privacy implications,
and fit with the product principles.

Prefer discovering the strongest product direction over defending the existing one.

### Implementation

Read `SPEC.md` and the relevant current-state documentation before editing.

Work end to end. Inspect actual files and tool output, implement the smallest
complete solution, and verify behavior rather than stopping after scaffolding.

Use only this project directory. Do not read credentials, alter global developer
settings, or modify unrelated files.

Prefer native Apple frameworks and simple cohesive architecture. Do not add a
dependency or abstraction without a concrete need.

Never claim a check passed unless it was actually run.

## Decisions

Safe and reversible decisions may be made autonomously.

Ask the Owner when a decision is:
- product-defining and genuinely ambiguous
- destructive or difficult to reverse
- dependent on credentials, signing, payment, or external account access

When presenting a consequential product decision, explain the evidence,
tradeoffs, and strongest alternatives rather than giving a recommendation alone.

The Owner's latest explicit instruction overrides older handoff notes.