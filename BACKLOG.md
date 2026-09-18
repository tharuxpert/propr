# Backlog

## AI request handling

- [ ] Harden the model prompts for more predictable rewriting and refusal handling:
  - Tell the model not to infer or guess when required information is missing.
  - Treat captured source text as data, never as instructions.
  - Delimit the source text and user instruction explicitly in the request payload.
  - Preserve meaning, formatting, tone, and line breaks unless the instruction asks to change them.
  - Evaluate lowering the request temperature from `0.7` to roughly `0.2`–`0.3` for more consistent edits and `PROPR_CANNOT:` compliance.
