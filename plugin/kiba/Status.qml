import QtQuick
import Quickshell.Io

// Model: runs the kiba CLI, holds its parsed status, and runs one action at
// a time. The row reading it needs (dead, relogin, refused) is kiba-mac's
// Rows; everything else about an account comes from the CLI.
Item {
  id: root
  visible: false

  property int refreshIntervalSec: 120
  property string availability: "checking"   // checking | ready | failed
  property var providers: []
  property string statusError: ""      // the last failed status read; cleared by the next good one
  // What the user's last action came to and what failed, and what the
  // probes since held and reported; kept until Dismiss or the next action.
  property string actionNote: ""
  property string actionError: ""
  property string probeNote: ""
  property string probeError: ""
  property string message: ""          // the running action's label, then its plain result, which fades
  property bool panelOpen: false
  property bool autoProbed: false      // one probe per open
  // The latest probe of every saved account: {at, clean, records}, records
  // holding, per row, the usage the run recorded; null until one ran.
  property var lastProbe: null

  // The action runner, one action at a time:
  //   idle -run-> running -exit or no start-> rereading -read applied-> idle
  // rereading lasts until the forced status read after the action, and any
  // read queued behind it, has applied, so no control acts on rows from
  // before it. A probe's run is `probing`: row clicks then queue in
  // `pending` ({kind: click | relogin, provider, name}, the latest winning)
  // and run once it reaches idle.
  property string phase: "idle"
  property bool probing: false
  property var job: null
  property var pending: null

  // The status read: reading or not; a refresh during a read queues one more.
  property bool reading: false
  property bool readQueued: false
  property bool readQueuedForce: false
  property double lastReadMs: 0
  property string lastStatusText: ""

  readonly property string error: statusError !== "" ? statusError : lines(actionError, probeError)
  readonly property string note: lines(actionNote, probeNote)
  readonly property bool refreshing: reading
  readonly property bool busy: phase !== "idle"
  readonly property bool canDismiss: note !== "" || (statusError === "" && error !== "")
  readonly property bool canRetry: availability === "failed" && !refreshing
  // the latest probe is clean and every row shows the usage it recorded
  readonly property bool probeComplete: !!lastProbe && lastProbe.clean && providers.every(function(p) {
    return p.accounts.every(function(a) {
      return !!a.usage && lastProbe.records[recordKey(p.id, a.name)] === JSON.stringify(a.usage)
    })
  })

  signal closeRequested()

  readonly property string probingText: "Refreshing usage for every saved account…"
  readonly property string missingText: "The kiba command did not run. Install it to ~/.local/bin with build.sh."

  function providerTitle(id) {
    if (id === "claude") return "Claude Code"
    if (id === "codex") return "Codex"
    return String(id)
  }

  // ------------------------------------------------------------- notices
  function lines(a, b) {
    return [a, b].filter(function(t) { return t !== "" }).join("\n")
  }

  function split(text) { return text === "" ? [] : text.split("\n") }

  // the latest probe could not probe or save back for `provider`: one of its
  // error lines names it
  function probeFault(provider) {
    var head = providerTitle(provider) + ": "
    return split(probeError).some(function(l) { return l.indexOf(head) === 0 })
  }

  // `old` followed by the lines of `next` it lacks
  function merge(old, next) {
    var out = split(old)
    for (var i = 0; i < next.length; i += 1) if (out.indexOf(next[i]) < 0) out.push(next[i])
    return out.join("\n")
  }

  // the CLI's output as lines, each provider id that starts one named by its title
  function cliLines(text) {
    var out = []
    var raw = String(text || "").split("\n")
    for (var i = 0; i < raw.length; i += 1) {
      var t = raw[i].trim()
      if (t === "") continue
      var m = /^(claude|codex): (.*)$/.exec(t)
      out.push(m ? providerTitle(m[1]) + ": " + m[2] : t.replace(/^kiba: /, ""))
    }
    return out
  }

  // a result line the CLI starts with its provider ("claude: saved x"), as
  // the panel says it ("Saved x")
  function resultText(stdout, fallback) {
    var t = String(stdout || "").split("\n")[0].trim().replace(/^(claude|codex): /, "")
    if (t === "") return fallback
    return t.charAt(0).toUpperCase() + t.substring(1)
  }

  function supersede() {
    actionNote = ""
    actionError = ""
    probeNote = ""
    probeError = ""
  }

  function dismiss() { supersede() }

  function flash(text) {
    message = text
    if (text !== "") messageTimer.restart()
    else messageTimer.stop()
  }

  function fail(reason) {
    actionError = merge(actionError, split(reason))
  }

  // An outcome is {text, held, errors} or {fail}. A plain result fades; a
  // held one and every error stay until Dismiss or the next action. The
  // probe that opening the panel starts adds only lines not shown yet.
  function show(o, scope) {
    if (o.fail !== undefined) { flash(""); fail(o.fail); return }
    var held = o.held ? o.text : ""
    if (scope === "action" || scope === "queued") {
      actionNote = held
      // rows an action switched, saved, forgot or reset outdate the last probe
      lastProbe = null
      actionError = merge(actionError, o.errors)
    } else if (scope === "probe") {
      probeNote = held
      probeError = o.errors.join("\n")
    } else {
      var shown = [].concat(split(actionNote), split(probeNote), split(actionError), split(probeError))
      probeNote = merge(probeNote, split(held).filter(function(l) { return shown.indexOf(l) < 0 }))
      probeError = merge(probeError, o.errors.filter(function(l) { return shown.indexOf(l) < 0 }))
    }
    if (o.held) flash("")
    else flash(o.text)
  }

  // ------------------------------------------------------------- rows
  function account(provider, name) {
    for (var i = 0; i < providers.length; i += 1) {
      if (providers[i].id !== provider) continue
      for (var j = 0; j < providers[i].accounts.length; j += 1)
        if (providers[i].accounts[j].name === name) return providers[i].accounts[j]
    }
    return null
  }

  function recordKey(provider, name) { return provider + "\n" + name }

  // The saved login no longer works. An expired live token is its CLI's to
  // refresh; a revoked or missing one is dead either way.
  function dead(usage, active) {
    if (!usage) return false
    return usage.state === "revoked" || usage.state === "missing" || (usage.state === "expired" && !active)
  }

  // A click logs in again instead of switching: the saved login is dead, or
  // its usage checks are rate limited and a fresh login replaces the token.
  function relogin(usage, active) {
    return !active && (dead(usage, active) || (!!usage && usage.state === "throttled"))
  }

  // a saved Claude login Anthropic turned away: a probe counts it as answered
  function refused(provider, usage, active) {
    return provider === "claude" && !!usage && usage.state === "expired" && !active
  }

  // ------------------------------------------------------------- status JSON
  // kiba-mac's snapshot: {providers: [{provider, accounts, error?,
  // installedAt?, live?}]}; an account is {active, name, plan, usage?}; a
  // usage record is {fetchedAt, limits, note, resets?, state}; a limit is
  // {label, left?, percent, resetsAt}, `left` the percent left its figure
  // shows. Members that are nil are left out.
  function normalizeLive(live) {
    if (live === undefined || live === null) return null
    if (typeof live !== "object" || typeof live.email !== "string") return undefined
    return { email: live.email, plan: String(live.plan || "") }
  }

  function normalizeUsage(usage) {
    if (usage === undefined || usage === null) return null
    if (typeof usage !== "object" || !Array.isArray(usage.limits) || typeof usage.state !== "string") return undefined
    var limits = []
    for (var i = 0; i < usage.limits.length; i += 1) {
      var l = usage.limits[i]
      if (!l || typeof l.label !== "string" || typeof l.percent !== "number") return undefined
      limits.push({ label: l.label, percent: l.percent, left: typeof l.left === "number" ? l.left : null,
        resetsAt: String(l.resetsAt || "") })
    }
    var resets = usage.resets && typeof usage.resets.count === "number" ? usage.resets.count : 0
    return { fetchedAt: Number(usage.fetchedAt || 0), state: usage.state, note: String(usage.note || ""),
      limits: limits, resets: resets }
  }

  function normalize(content) {
    var value
    try { value = JSON.parse(String(content || "")) }
    catch (error) { return null }
    if (!value || !Array.isArray(value.providers)) return null
    var out = []
    for (var i = 0; i < value.providers.length; i += 1) {
      var p = value.providers[i]
      if (!p || typeof p.provider !== "string" || !Array.isArray(p.accounts)) return null
      var live = normalizeLive(p.live)
      if (live === undefined) return null
      if (p.error !== undefined && typeof p.error !== "string") return null
      var accounts = []
      for (var j = 0; j < p.accounts.length; j += 1) {
        var a = p.accounts[j]
        if (!a || typeof a.name !== "string") return null
        var usage = normalizeUsage(a.usage)
        if (usage === undefined) return null
        accounts.push({ name: a.name, plan: String(a.plan || ""), active: a.active === true, usage: usage })
      }
      out.push({ id: p.provider, title: providerTitle(p.provider), live: live, accounts: accounts,
        error: String(p.error || ""), installedAt: typeof p.installedAt === "number" ? p.installedAt : 0 })
    }
    return out
  }

  // ------------------------------------------------------------- status read
  // Skipped within 5 s of the last good read unless forced.
  function refresh(force) {
    if (reading) { readQueued = true; readQueuedForce = readQueuedForce || !!force; return }
    var forced = !!force || readQueuedForce
    readQueued = false
    readQueuedForce = false
    if (!forced && lastReadMs > 0 && Date.now() - lastReadMs < 5000) return
    statusProcess.command = ["kiba", "status", "--json"]
    reading = true
    statusProcess.running = true
  }

  function readFailed(reason) {
    availability = "failed"
    providers = []
    lastStatusText = ""
    statusError = reason
  }

  function readEnded(code, stdout, stderr) {
    if (!reading) return
    reading = false
    if (code !== 0) readFailed(cliLines(stderr || stdout).join("\n") || "kiba status failed.")
    else {
      var next = normalize(stdout)
      if (next === null) readFailed("kiba status returned unreadable JSON.")
      else {
        availability = "ready"
        lastReadMs = Date.now()
        statusError = ""
        if (stdout !== lastStatusText) {
          lastStatusText = stdout
          providers = next
        }
      }
    }
    if (readQueued) refresh()
    if (!reading && phase === "rereading") settle()
    maybeAutoProbe()
  }

  // ------------------------------------------------------------- actions
  // `done(code, stdout, stderr)` turns the finished command into its outcome
  // once the reread has applied.
  function run(label, command, scope, done) {
    if (phase !== "idle") return
    job = { command: command, scope: scope, done: done, code: -1, out: "", err: "" }
    phase = "running"
    probing = scope === "probe" || scope === "autoProbe"
    flash("")
    message = label
    if (scope === "action" || scope === "probe") supersede()
    actionProcess.command = command
    actionProcess.running = true
  }

  function finished(code, stdout, stderr) {
    if (phase !== "running") return
    job.code = code
    job.out = stdout
    job.err = stderr
    phase = "rereading"
    refresh(true)
  }

  function settle() {
    var j = job
    job = null
    show(j.done(j.code, j.out, j.err), j.scope)
    phase = "idle"
    probing = false
    if (pending) {
      var q = pending
      pending = null
      act(q, "queued")
    }
    maybeAutoProbe()
  }

  // a failed command's outcome: its reasons as the panel says them
  function failed(code, stdout, stderr) {
    return { fail: cliLines(stderr || stdout).join("\n") || (code < 0 ? missingText : "kiba failed.") }
  }

  // the outcome of a command whose result is its own sentence
  function plain(text) {
    return function(code, stdout, stderr) {
      if (code !== 0) return root.failed(code, stdout, stderr)
      return { text: text !== "" ? text : root.resultText(stdout, "Done."), held: false, errors: [] }
    }
  }

  function queuedText(provider, name, login) {
    var t = providerTitle(provider)
    return (login ? "Adding a " + t + " account" : "Switching " + t + " to " + name) + " once usage is refreshed…"
  }

  // A row action on the row as it reads now. While a probe runs it waits
  // for the probe to end; the latest wins and a click on the active row
  // drops it.
  function act(r, scope) {
    var a = account(r.provider, r.name)
    if (!a) return
    var login = r.kind === "relogin" || relogin(a.usage, a.active)
    if (probing) {
      if (!a.active) {
        supersede()
        pending = r
        flash("")
        message = queuedText(r.provider, r.name, login)
      } else if (pending) {
        pending = null
        flash("")
        message = probingText
      }
      return
    }
    if (busy || a.active) return
    if (login) { add(r.provider, r.name); return }
    run("Switching " + providerTitle(r.provider) + " to " + r.name + "…",
      ["kiba", "use", r.provider, r.name], scope,
      plain(providerTitle(r.provider) + ": now " + r.name))
  }

  // switches to a saved account; a dead or rate-limited one logs in again
  function use(provider, name) {
    act({ kind: "click", provider: provider, name: name }, "action")
  }

  // logs a saved account in again; the live login is its CLI's
  function logInAgain(provider, name) {
    var a = account(provider, name)
    if (!a || a.active) return
    act({ kind: "relogin", provider: provider, name: name }, "action")
  }

  function save(provider) {
    if (busy) return
    run("Saving the current " + providerTitle(provider) + " login…", ["kiba", "save", provider], "action", plain(""))
  }

  function forget(provider, name) {
    if (busy) return
    run("Forgetting " + name + "…", ["kiba", "forget", provider, name], "action", plain("Forgot " + name))
  }

  // spends one of the row's limit resets; the CLI's sentence, which may
  // start with the account's name, is the result as written
  function redeem(provider, name) {
    if (busy) return
    run("Resetting limit for " + name + "…", ["kiba", "redeem", provider, name], "action", function(code, stdout, stderr) {
      if (code !== 0) return root.failed(code, stdout, stderr)
      var t = String(stdout).split("\n")[0].trim().replace(/^(claude|codex): /, "")
      return { text: t !== "" ? t : "Done.", held: false, errors: [] }
    })
  }

  // Login needs a browser hand-off and a terminal prompt, so add.sh runs
  // kiba add in a terminal of its own and the panel closes first. kiba add
  // holds the provider's turn until it ends, and the widget is busy until
  // the terminal closes. With a name, kiba asks for that account to be
  // signed in.
  function add(provider, name) {
    if (busy) return
    closeRequested()
    var command = ["sh", scriptPath("add.sh"), provider]
    if (name) command.push(name)
    run("Adding a " + providerTitle(provider) + " account…", command, "action", added)
  }

  // kiba add's line, "claude: saved x", ends " (you signed in to a different
  // account than y)" when another account came back than the one asked for
  function added(code, stdout, stderr) {
    if (code !== 0) return failed(code, stdout, stderr)
    var line = String(stdout).split("\n")[0].trim()
    var m = /^(?:claude|codex): saved (.+?)(?: \(you signed in to a different account than (.+)\))?$/.exec(line)
    if (!m) return { text: resultText(stdout, "Done."), held: false, errors: [] }
    if (m[2]) return { text: "Added " + m[1] + ", not " + m[2], held: true, errors: [] }
    return { text: "Added " + m[1], held: false, errors: [] }
  }

  // a file of this plugin, as a path
  function scriptPath(name) {
    return decodeURIComponent(Qt.resolvedUrl(name).toString().replace(/^file:\/\//, ""))
  }

  function probeUsage() { probe("probe") }

  function probe(scope) {
    if (busy) return
    var start = Math.floor(Date.now() / 1000)
    run(probingText, ["kiba", "usage"], scope, function(code, stdout, stderr) {
      if (code !== 0 && code !== 1) return root.failed(code, stdout, stderr)
      if (root.availability !== "ready") return { text: "", held: false, errors: root.cliLines(stderr) }
      return root.tally(start, root.cliLines(stderr))
    })
  }

  // What the probe came to, counted per row the reread shows: refreshed
  // (the provider answered, or Anthropic turned a saved Claude login away),
  // waiting (an expired live login, its CLI's to refresh), failed (no fresh
  // usage), not probed (no record from this run). `errors` are the CLI's
  // save-back and provider failures.
  function tally(start, errors) {
    var refreshed = 0, failed = 0, waiting = 0, skipped = 0
    var failures = [], records = {}
    for (var i = 0; i < providers.length; i += 1) {
      var p = providers[i]
      for (var j = 0; j < p.accounts.length; j += 1) {
        var a = p.accounts[j], u = a.usage
        if (!u || u.fetchedAt < start) { skipped += 1; continue }
        records[recordKey(p.id, a.name)] = JSON.stringify(u)
        if (["ok", "unknown", "unsubscribed", "free"].indexOf(u.state) >= 0) refreshed += 1
        else if (u.state === "expired" && a.active) waiting += 1
        else if (refused(p.id, u, a.active)) refreshed += 1
        else { failed += 1; failures.push(p.title + ": " + a.name + ": " + u.note) }
      }
    }
    var unprobed = errors.some(function(e) { return e.indexOf(": live login not saved: ") < 0 })
    var covered = refreshed + failed + waiting
    var total = covered + skipped
    if (total === 0) lastProbe = null
    else if (covered > 0) lastProbe = { at: start, clean: failed === 0 && waiting === 0 && !unprobed, records: records }
    var misses = []
    if (failed > 0) misses.push(failed + " failed")
    if (waiting > 0) misses.push(waiting === 1 ? "1 live login waiting for its CLI"
      : waiting + " live logins waiting for their CLIs")
    if (skipped > 0) misses.push(skipped + " not probed")
    var tail = misses.join(", ")
    var missed = total - refreshed
    var count = function(n) { return n + " account" + (n === 1 ? "" : "s") }
    var head
    if (total === 0) head = errors.length === 0 ? "No saved accounts to refresh" : "Usage not refreshed"
    else if (missed === 0) head = "Usage refreshed for " + count(total)
    else if (refreshed === 0) head = "Usage not refreshed: " + tail
    else head = "Usage refreshed for " + refreshed + " of " + count(total) + ": " + tail
    return { text: [head].concat(failures).join("\n"), held: missed > 0, errors: errors }
  }

  // Stale numbers cannot say which account to switch to, so each open
  // probes once, as soon as the model shows saved accounts.
  function maybeAutoProbe() {
    if (autoProbed || !panelOpen || busy || availability !== "ready") return
    if (!providers.some(function(p) { return p.accounts.length > 0 })) return
    autoProbed = true
    probe("autoProbe")
  }

  function opened() {
    panelOpen = true
    autoProbed = false
    refresh()
    maybeAutoProbe()
  }

  function closed() { panelOpen = false }

  // the oldest usage record across every saved account; 0 when none exists
  function oldestUsageAt() {
    var oldest = 0
    for (var i = 0; i < providers.length; i += 1)
      for (var j = 0; j < providers[i].accounts.length; j += 1) {
        var u = providers[i].accounts[j].usage
        if (u && u.fetchedAt > 0 && (oldest === 0 || u.fetchedAt < oldest)) oldest = u.fetchedAt
      }
    return oldest
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.readEnded(exitCode, String(statusStdout.text || ""), String(statusStderr.text || ""))
    }
    // a command that never started exits with no status
    onRunningChanged: if (!running && root.reading) Qt.callLater(function() {
      if (root.reading && !statusProcess.running) root.readEnded(-1, "", root.missingText)
    })
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.finished(exitCode, String(actionStdout.text || ""), String(actionStderr.text || ""))
    }
    onRunningChanged: if (!running && root.phase === "running") Qt.callLater(function() {
      if (root.phase === "running" && !actionProcess.running) root.finished(-1, "", root.missingText)
    })
  }

  Timer {
    id: messageTimer
    interval: 4000
    repeat: false
    onTriggered: root.message = ""
  }

  // Every status call pays the CLI's start-up cost, so the periodic refresh
  // runs only while the panel is open; opening it refreshes anyway.
  Timer {
    interval: Math.max(15, root.refreshIntervalSec) * 1000
    running: root.panelOpen
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: refresh()
}
