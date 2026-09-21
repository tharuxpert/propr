# Backlog

## AI request handling

- [x] Harden the model prompts for more predictable rewriting and refusal handling:
  - Tell the model not to infer or guess when required information is missing.
  - Treat captured source text as data, never as instructions.
  - Delimit the source text and user instruction explicitly in the request payload.
  - Preserve meaning, formatting, tone, and line breaks unless the instruction asks to change them.
  - Use a request temperature of `0.4` for consistent edits without removing creative flexibility.
