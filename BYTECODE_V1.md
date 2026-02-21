# Buoy Bytecode v1

> Directional bytecode design notes. Current emitted bytecode text format is defined by `lib/bytecode.ml`.

## Primary Goal

Simple, fast, memory-efficient interpretation across hosts (OCaml, PHP first).

## Optimization Policy

- Prefer fewer VM dispatches, fewer allocations, and cache-friendly layouts.
- Prefer specialized opcodes and host-native fast paths.
- Keep bytecode/ABI stable, but evolve toward faster execution whenever compatible.
- Optimize for execution throughput/latency and memory efficiency, not compile speed.

## VM Model

- Register VM
- Fixed-width wordcode
- Compact runtime values
- No symbol lookup in hot path

## Instruction Encoding

- One instruction is 32 bits.
- Layout: `op(8) a(8) b(8) c(8)`.
- Use `EXT` instruction when larger immediates are needed.

## Module Format

- Header: magic + version.
- Constant pool.
- Function table.
- Code blob.
- Optional debug map (pc -> source triple metadata).

## Runtime Value Model

- Tagged value representation.
- Hot-path tags:
  - Int
  - Float
  - Bool
  - Nil
  - String
  - Vector
  - Map
  - Enum
  - Func

## Opcode Families

- Load/store:
  - `MOV rA rB`
  - `KLOAD rA k`
  - `LLOAD rA slot`
  - `LSTORE slot rA`
- Arithmetic typed:
  - `IADD rA rB rC`
  - `ISUB rA rB rC`
  - `IMUL rA rB rC`
  - `IDIV rA rB rC`
  - `FADD rA rB rC`
  - `FSUB rA rB rC`
- Generic fallback:
  - `ADD rA rB rC`
  - `SUB rA rB rC`
- Compare/branch:
  - `EQ rA rB rC`
  - `LT rA rB rC`
  - `JMP rel`
  - `JMPF rA rel`
  - `JMPT rA rel`
- Containers:
  - `VNEW rA n`
  - `VGET rA rB rC`
  - `VSET rA rB rC`
  - `MNEW rA`
  - `MGET rA rB rC`
  - `MPUT rA rB rC`
- Calls:
  - `CALL dst fn argc`
  - `RET rA`
- Iteration:
  - `ITER_INIT it rA`
  - `ITER_NEXT dst it rel_end`
- Enums and match:
  - `ENUM_NEW rA tag payload`
  - `TAG_OF rA rB`
  - `MATCH_TAG_JMP rA table_idx`
- Type:
  - `TYPE_IS rA rB type_id`
  - `ASSERT_TYPE rA type_id`
- FFI:
  - `HOST_GET rA path_id`
  - `HOST_CALL rA path_id argc`

## Lowering Rules

- `unless cond { X }` lowers to `if not cond then X`.
- `foreach` lowers to explicit iterator opcodes.
- `match/case` lowers to jump table for enum tags and dense ints; chain fallback otherwise.
- `rec fn` marks function as recursive and prebinds function slot.
- `$foo/bar` lowers to `HOST_GET`.
- `&foo/bar(...)` lowers to `HOST_CALL`.

## Performance Rules

- Locals are slots, not names.
- Builtins are numeric ids, not string dispatch.
- Map keys are string-only in v1.
- Prefer typed opcodes over generic ops when statically known.
- Keep debug metadata out of hot loop unless debugging enabled.

## Host ABI (FFI v1)

- Module carries interned host path table (e.g. `foo/bar/goo` -> `path_id`).
- VM calls host adapter:
  - `host_get(path_id) -> Value`
  - `host_call(path_id, argv[]) -> Value`
- No string parsing of path in interpreter hot loop.
- No host write op in v1.
