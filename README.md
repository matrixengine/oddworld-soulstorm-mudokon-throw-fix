# Mudokon Throw Fix

Unofficial patch for **Oddworld: Soulstorm Enhanced Edition** (Steam, PC) that fixes
followers in Aggressive mode refusing to throw at Sligs, and wasting ammo when they do.

Modded by MatrixEngine a.k.a GameMasterUK.

## Summary

| # | Problem | After the fix |
|---|---------|---------------|
| 1 | Followers stand silent and get shot after you load a checkpoint | They throw straight away from a fresh launch |
| 2 | Followers stop throwing for good after a throw is interrupted | Switching to Passive mid-throw and back no longer breaks them |
| 3 | Followers keep throwing cans at a Slig that is already down | They stop once the Slig is down |

All three were confirmed in play on *Reunion at the Old Trellis*.

## Disclaimer

Use this at your own risk. It is an unofficial, fan-made patch that modifies a game
file. It is not made, endorsed or supported by Oddworld Inhabitants or anyone else
connected with the game. It was tested on one PC and one game build, and is provided as
is, with no warranty of any kind. The author accepts no responsibility for any problem
that follows from using it, including a game that will not start, lost progress, or
changes you make to Windows security settings.

The patcher keeps a backup of the original file, and `MudokonThrowFix-Restore.cmd` or
Steam's "Verify integrity of game files" puts the game back as it was.

## How to use it

Close the game first, then double-click one of these:

| File | What it does |
|------|--------------|
| `MudokonThrowFix-Apply.cmd` | Applies all three fixes |
| `MudokonThrowFix-Apply-Fixes1and2.cmd` | Applies fixes 1 and 2 only (see *Smart App Control* below) |
| `MudokonThrowFix-Restore.cmd` | Puts the original game file back |

The patch changes one file, `GameAssembly.dll`, in the game folder. The first time it
runs it saves the untouched original next to it as
`GameAssembly.dll.pre-mudokon-fix.bak`. Keep that file: Apply and Restore both need it.

Your existing saves and checkpoints work as they are. Nothing needs replaying.

## The issues, one by one

### 1. Followers silent after loading a checkpoint

**What you see:** you load a checkpoint, Sligs come up, and every follower just stands
there and gets shot, even though they have ammo and are in Aggressive mode. It can
"fix itself" after many minutes of play.

**What was wrong:** each follower remembers the time of its last throw, and must wait
2.5 seconds between throws. The checkpoint saves that time as a raw reading of the
game clock. But the game clock restarts from zero every time you launch the game. So
after resuming in a new session, the saved "last throw" time is in the future, the
2.5-second check can never pass, and nobody throws until the new session has been
running as long as the old one had been.

On the test machine the four followers had saved times of 936 to 983 seconds, in a
session that was two and a half minutes old. They would have stayed silent for about
16 minutes.

**What was fixed:** loading a checkpoint no longer restores the two saved throw times
(one for cans, one for water bottles). A freshly loaded follower can throw at once.

### 2. Followers stuck for good after an interrupted throw

**What you see:** followers that were throwing fine stop attacking altogether, and
switching between Passive and Aggressive does not bring them back.

**What was wrong:** when a follower starts a throw it is flagged as "throw in
progress". While that flag is set, the game leaves the follower's target alone. The
flag is only cleared when the throw finishes or is formally aborted. Three things pull
a follower out of a throw without clearing it: switching to Passive, Abe bumping into
a wall (followers stop to laugh), and a possession ending. If the Slig that follower
was aiming at then dies, the follower is left with the flag stuck and a corpse as its
target, and the game skips it from then on.

**What was fixed:** the flag is now cleared whenever a follower leaves the throw
state, however it leaves. As a safety net, the flag is also ignored unless the
follower really is in the throw state.

### 3. Cans wasted on a Slig that is already down

**What you see:** a Slig goes down, and the other followers each throw one more can at
it anyway.

**What was wrong:** the game only allows one special item in flight per Slig, so the
other followers wait their turn. But a follower that has started winding up counts as
"committed" and stops checking whether its target is still worth hitting. Once the
first can lands and the Slig drops, each waiting follower takes a can and throws it at
the Slig on the floor.

**What was fixed:** a committed follower now gives up its wind-up as soon as its
target is dead, knocked out or bound, as long as it has not yet taken a can in hand.
It then goes back to following and can pick a new target.

Two cases are left alone on purpose: a follower already holding the can still throws
it, and a can already in the air cannot be recalled. So expect far fewer wasted cans,
not always zero.

## Things to know

**Smart App Control.** Windows Smart App Control judges every unsigned program file,
and a refused `GameAssembly.dll` means the game will not start. On the PC this was made
on:

- With Smart App Control on, it accepted fixes 1 and 2, but refused the file whenever
  all three fixes were applied.
- Switching it off is what allowed all three fixes to be applied and played.
- When it was switched back on afterwards, Windows did not complain again, and the game
  still runs with all three fixes.

So it only objected when all three were applied while it was switched on. If the game
will not start after applying, run `MudokonThrowFix-Apply-Fixes1and2.cmd`, or apply all
three with Smart App Control off as above. Be aware that on some versions of Windows,
Smart App Control cannot be switched back on once it is off.

**Game updates.** A Steam "Verify integrity of game files" or a game update replaces
`GameAssembly.dll` and removes the patch. The patcher only works on the exact game
build it was made for and will refuse to touch any other, so after an update it would
need redoing.

**Antivirus.** Security software may flag a modified game file. Nothing here runs
alongside the game or stays in memory; the patch is a few hundred changed bytes in one
file.

**Not changed.** Throw range, accuracy, ammo counts, Slig behaviour and difficulty are
untouched.

## Technical notes

### Target

- Game build: Unity 2019.4.30 (IL2CPP).
- Original `GameAssembly.dll` SHA-256:
  `D8F3F565159D76402BD29DB28A10A5A645821C833B9DD6742ACA4E69E10F9226`
- Every address below is an RVA in `GameAssembly.dll`. All patched code is in the
  `il2cpp` section. File offset = RVA + (section raw offset - section virtual address),
  which for `il2cpp` in this build is RVA - 0x1600.

### Command line

```
powershell -File MudokonThrowFix.ps1 -Action Status
powershell -File MudokonThrowFix.ps1 -Action Apply   [-Fixes 1,2,3]
powershell -File MudokonThrowFix.ps1 -Action Restore
```

`-Fixes` takes any combination of 1, 2 and 3 (default: all three). `Status` reports
each fix as applied, not applied or partly applied, and whether the file has any other
differences from the original.

Apply always rebuilds from the pristine bytes, so it can be re-run to switch fixes on
or off. The pristine bytes are the file itself if it is still untouched, otherwise the
backup, which must match the SHA-256 above. Before using the backup the script checks
the installed file is the same build: identical size and identical first 0x200 bytes
(the DOS/PE headers: timestamp, sizes, entry point). Each patch site's original bytes
are checked before anything is written, and the result is read back and compared
afterwards.

### Fix 1 in detail: stale throw timestamps

`MudokonSlave.MudokonSlaveSaveState` stores each follower's `m_fLastThrow` and
`m_fLastWaterThrow` as raw `UnityEngine.Time.time` values, and `Restore` writes them
straight back. `Time.time` restarts from zero on every launch, so after resuming from
a checkpoint the saved value is in the future. `MudokonSlaveManager.UpdateMudThrowQueues`
and `CanThrowAtTarget` both require `Time.time - m_fLastThrow >= 2.5` (the
`delayBetweenIndividualThrows` setting), which stays negative until the new session has
run as long as the old one had when that follower last threw.

The fix replaces two instructions in `Restore` with 8-byte NOPs
(`0F 1F 84 00 00 00 00 00`), so the timestamps are no longer overwritten. A freshly
loaded follower starts at 0; a same-session reload keeps its current, valid value.

| RVA | Original instruction | Field |
|-----|----------------------|-------|
| 0x148DECA | `movss [rsi+0xB70], xmm1` | `m_fLastThrow` |
| 0x148DEDB | `movss [rsi+0xB74], xmm0` | `m_fLastWaterThrow` |

Confirmed on a live game.

### Fix 2 in detail: stuck `throwInProgress` flag

`MudokonSlave.InitThrow` sets `throwInProgress` (byte at +0xFB0) for a whole throw
sequence. While it is set, the follower skips its own target validity check and
`UpdateMudThrowQueues` will not clear its target. `MudokonSlaveThrowExit` never clears
the flag, yet `MudokonSlaveThrowExecute` can leave the throw state mid-sequence: when
followers are switched to Passive, when Abe bumps a wall (the follower laughs), or when
a possession ends. If the targeted Slig then dies, the follower keeps a stuck flag and a
corpse as its target, and is skipped every frame from then on.

Two hooks jump into unused space at the end of the `il2cpp` section.

| RVA | What it is |
|-----|------------|
| 0x11ECB2A | Hook site in `MudokonSlaveThrowExit`, originally `mov byte ptr [rbx+0xFA8], 0`. Replaced by `jmp` to stub 1 plus a 2-byte NOP. |
| 0x11ECB31 | Where stub 1 returns to. |
| 0x149BA91 | Hook site in `UpdateMudThrowQueues`, originally `xor ecx,ecx` / `cmp [r14+0xFB0],cl` / `sete cl`. Replaced by `jmp` to stub 2 plus a 7-byte NOP. |
| 0x149BA9D | Where stub 2 returns to. |
| 0x2149F9C - 0x214A000 | The cave: 100 bytes, starting at the first byte past the section's original VirtualSize. Filled with `CC`, with the two stubs laid over it. |
| 0x2149FA0 | Stub 1. |
| 0x2149FC0 | Stub 2. |

The `il2cpp` section's VirtualSize is raised from 0x1E54F9C to 0x1E55000, equal to its
SizeOfRawData, so Windows maps the cave into memory.

Stub 1 runs the original instruction, then clears `throwInProgress` and
`clearThrowTargetAfterCurrentThrow` (the byte after it) in one write:

```
mov  byte ptr [rbx+0xFA8], 0     ; original instruction
mov  word ptr [rbx+0xFB0], 0     ; throwInProgress + clearThrowTargetAfterCurrentThrow
jmp  0x11ECB31
```

Stub 2 computes `cl = (state != MudokonSlaveThrow) || !throwInProgress`, so the flag is
only honoured while the follower really is in the throw state (state 0x819):

```
xor  ecx, ecx
cmp  dword ptr [r14+0x70], 0x819
jne  +9                          ; not in the throw state -> mov cl, 1
cmp  byte ptr [r14+0xFB0], cl
jne  +2                          ; flag set -> leave cl = 0
mov  cl, 1
jmp  0x149BA9D
```

Found by code analysis, then confirmed in play.

### Fix 3 in detail: cans thrown at a downed Slig

The game allows one "special ammo" item in flight per target, so followers queue up.
But a follower whose first wind-up at a target started with no delay is marked
committed (`throwInProgress`), and `MudokonSlaveThrowExecute` then skips its target
validity check. When the first can drops the Slig and the special-ammo marker clears,
each waiting follower takes a can and throws it at the downed Slig.

`GoToThrow` now stores 0x81 instead of 1 in `throwInProgress`, so "committed wind-up"
(1) and "throw animation running" (0x81) can be told apart. Every existing reader of
the flag only tests for non-zero, so nothing else changes. A hook on the validity gate
then aborts a committed wind-up when the follower has not yet taken a special item in
hand and its target is dead, or is a `PantsSlig` whose brain is Death, KnockedOut or
Binded.

| RVA | What it is |
|-----|------------|
| 0x11E9EFE | In `GoToThrow`: the immediate byte of `mov byte ptr [rbx+0xFB0], 1`, changed from 0x01 to 0x81. |
| 0x11EC417 | Hook site, the validity gate in `MudokonSlaveThrowExecute`, originally `cmp [rbx+0xFB0], al` / `jne +0x4D`. Replaced by `jmp` to the gate stub plus a 3-byte NOP. |
| 0x11EC41F | GateCheck: the original target validity check. |
| 0x11EC45D | GateAbort: the existing `AbortThrow(); return` block. |
| 0x11EC46C | GateSkip: continue the throw sequence. |
| 0x2C2DC28 | Global slot holding the `Il2CppClass*` of `PantsSlig`. |
| 0x11D2B70 | `MudokonSlave.OnDrawGizmosSelected`, an editor-only method that nothing calls in the shipped game. |
| 0x11D2B80 | The gate stub, 16 bytes into that method. |

The first 119 bytes of the dead method are replaced: its entry becomes a plain `ret`,
followed by 15 bytes of `CC` padding, then the 103-byte gate stub. The script carries
those 119 original bytes so it can check them before patching.

The gate stub (offsets are from 0x11D2B80):

```
+0    cmp  byte ptr [rbx+0xFB0], 1
+7    jb   GateCheck                 ; flag 0: run the original check
+13   ja   skip                      ; flag 0x81: throw animation, leave alone
+15   mov  eax, [rbx+0xFB8]          ; projectilePrepared
+21   test eax, eax
+23   jz   +30                       ; nothing in hand
+25   cmp  eax, 2                    ; Rock
+28   jne  skip                      ; holding a special item
+30   mov  rcx, [rbx+0xB88]          ; m_cCurrentThrowTarget
+37   test rcx, rcx
+40   jz   skip
+42   mov  rcx, [rcx+0x10]           ; Target
+46   test rcx, rcx
+49   jz   skip
+51   cmp  dword ptr [rcx+0x3A4], 0  ; m_nHealth
+58   jle  abort
+60   mov  rdx, [rcx]                ; klass
+63   cmp  rdx, [rip+PantsSligClass]
+70   jne  skip                      ; not a PantsSlig
+72   mov  eax, [rcx+0xEC8]          ; m_eBrain
+78   cmp  eax, 9                    ; Death
+81   je   abort
+83   cmp  eax, 16                   ; KnockedOut
+86   je   abort
+88   cmp  eax, 18                   ; Binded
+91   jne  skip
+93   abort: jmp GateAbort
+98   skip:  jmp GateSkip
```

A follower already holding a special item, or mid-throw, is deliberately left alone so
the game's special-ammo bookkeeping is not disturbed.

Found by code analysis, then confirmed in play: no cans are repeatedly thrown at a downed Slig.

### Smart App Control detail

All three fixes were confirmed in-game with Windows Smart App Control switched off.
With it on, the PC this was developed on accepted the fixes-1-and-2 build but rejected
every later variant of the DLL, including a test copy with a single padding byte
changed, with error 4551: "An Application Control policy has blocked this file". A
blocked `GameAssembly.dll` means the game cannot start.
`MudokonThrowFix-Apply-Fixes1and2.cmd` goes back to the build it accepted.

Switching Smart App Control off is what allowed the three-fix build to be applied and
played. After testing it was switched back on, and Windows has not complained since:
the three-fix build that was applied while it was off still loads and the game runs.
The only refusals were for three-fix builds applied while Smart App Control was on.
Why a file applied while it was off stays accepted is not known, and re-applying the
patch with it on has not been tried since.

### How the script builds jumps

- 32-bit relative jumps are computed from the address of the `E9` opcode (or of the
  second byte of a `0F 8x` conditional jump): `target - (address + 5)`.
- 8-bit relative jumps are computed from the address of the 2-byte short jump:
  `target - (address + 2)`. The script stops if one is out of range.
- The gate stub must come out at exactly 103 bytes, and the dead-method patch at
  exactly 119, or the script stops without writing anything.
