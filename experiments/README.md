# Experiments

This fork replaced the Codex integration with Claude Code, so the Codex cloud
benchmark and its offline protocol checks were removed here rather than
rewritten against an assistant they never measured. They remain in upstream
[evindor/keystroke](https://github.com/evindor/keystroke) and in this fork's
first commit.

Local Gemma audio and text runtimes were removed earlier, upstream. Quantized
Gemma 4 E2B W4A16 did run on Intel XPU with vLLM, but measured model allocation
was 6.84 GiB and total service memory about 12.4 GiB; startup was roughly 90
seconds. Those resource costs did not fit the laptop experience. Earlier code
and detailed results remain in upstream git history (`0325fb6`). The v1 voice
tag is unchanged.

Keystroke retains Vulkan Whisper for speech and uses Claude Code for reasoning.
See [current verification](../docs/claude-integration-verification.md).
