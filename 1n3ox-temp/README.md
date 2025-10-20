# 1N.3OX - Receiving Bay Protocol
**Version:** 1.0  
**Purpose:** Where work arrives at any base

---

## What is 1N.3OX?

**The receiving bay for your bases.**

Every base has a `!1N.3OX [BASENAME]/` folder where:
- New work drops
- Files arrive from CMD.BRIDGE
- Instructions come in
- Nothing flies in unaccounted for

---

## Structure

```
[Any Base]/
└── !1N.3OX [BASENAME]/
    ├── (Files arrive here)
    └── (Get processed by base OPS)
```

**Example:**
```
RVNx.BASE/
└── !1N.3OX RVNX.BASE/
    └── new_sync_task.md  ← Arrives here

SYNTH.BASE/
└── !1N.3OX SYNTH.BASE/
    └── deploy_request.yaml  ← Arrives here
```

---

## How It Works

1. File drops into `!1N.3OX [BASENAME]/`
2. Base OPS detects it
3. Base .3ox processes it according to brain
4. Results go to `0UT.3OX/`

**That's it. Receiving bay.**

---

## Paired With

**0UT.3OX** - Outgoing (files leaving base)  
**1N.3OX** - Incoming (files arriving at base)

**Together = bidirectional flow**

---

**Status:** Protocol specification

:: ∎

