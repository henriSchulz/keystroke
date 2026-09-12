.pragma library

// Hand a prompt to an assistant without the clipboard. Every link below was
// verified on 2026-09-06 (Omarchy 4.0.2) by opening it and reading the window:
//
//   claude-desktop 1.40609.1   claude://claude.ai/new?q=<prompt>&surface=chat
//                              opens a new chat with the prompt in the composer.
//                              It is the link Anthropic's own GNOME search
//                              provider builds (resources/gnome-search-provider/
//                              searchProvider.js, LaunchSearch). The app rejects
//                              a q that starts with "/" (slash commands), so a
//                              leading slash is padded with a space.
//                              claude://code/new?q=<prompt> starts a Claude Code
//                              session the same way.
//   chatgpt.com                ?prompt= prefills; ?q= sends immediately.
//   claude.ai                  /new?q= prefills; there is no auto-send form.
//
// Claude has its own provider with an inline conversation and a CLI hand-off,
// so this file only builds the external one-shot launches. ChatGPT keeps no
// desktop or CLI route in this fork and always opens in the browser.
//
// Nothing here runs at query time except string building; activation is always
// an explicit Enter.

var MAX_PROMPT = 2000

function clip(prompt) {
  var text = String(prompt === undefined || prompt === null ? "" : prompt).trim().slice(0, MAX_PROMPT)
  return text.charAt(0) === "/" ? " " + text : text
}

function encode(prompt) { return encodeURIComponent(clip(prompt)) }

function claudeDesktopUrl(prompt) { return "claude://claude.ai/new?q=" + encode(prompt) + "&surface=chat" }
function claudeCodeUrl(prompt) { return "claude://code/new?q=" + encode(prompt) }
function claudeWebUrl(prompt) { return "https://claude.ai/new?q=" + encode(prompt) }
function chatgptWebUrl(prompt, autoSend) { return "https://chatgpt.com/?" + (autoSend ? "q=" : "prompt=") + encode(prompt) }
function googleUrl(query) { return "https://www.google.com/search?q=" + encodeURIComponent(String(query || "").trim()).replace(/%20/g, "+") }

// Prefer the app's own launcher when it is on PATH (the scheme handler may not
// be registered in mimeapps.list); otherwise let xdg-open resolve the scheme.
function openLink(bin, url, available) {
  return available && available[bin] ? { type: "exec", argv: [bin, url] } : { type: "url", url: url }
}

// One row plan per assistant. `available` maps binary name -> true for
// claude-desktop and claude (CLI).
function plan(assistant, mode, autoSend, available, prompt) {
  var avail = available || {}
  var claude = assistant === "claude"
  if (claude && mode === "cli" && avail["claude"])
    return { id: assistant, target: "claude-cli", title: "Ask Claude Code",
             subtitle: "Terminal · new claude session with your prompt", verb: "Open terminal",
             effect: { type: "exec", argv: ["omarchy-launch-terminal", "claude", clip(prompt)] } }
  if (claude && mode === "desktop" && avail["claude-desktop"])
    return { id: assistant, target: "claude-desktop", title: "Ask Claude",
             subtitle: "Claude desktop · new chat, prompt ready to send", verb: "Open Claude",
             effect: openLink("claude-desktop", claudeDesktopUrl(prompt), avail) }
  var why = mode === "browser" ? "" : (mode === "cli" ? " · CLI not installed" : " · desktop app not installed")
  if (claude)
    return { id: assistant, target: "claude-web", title: "Ask Claude",
             subtitle: "claude.ai · prompt ready to send" + why, verb: "Open Claude",
             effect: { type: "url", url: claudeWebUrl(prompt) } }
  return { id: assistant, target: "chatgpt-web", title: "Ask ChatGPT",
           subtitle: "chatgpt.com · " + (autoSend ? "sends your prompt" : "prompt ready to send") + (mode === "browser" ? "" : " · browser only"), verb: "Open ChatGPT",
           effect: { type: "url", url: chatgptWebUrl(prompt, autoSend) } }
}
