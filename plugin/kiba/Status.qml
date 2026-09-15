import QtQuick
import Quickshell
import Quickshell.Io

// Model: runs the kiba CLI and holds its parsed status. No account logic lives here.
Item {
  id: root
  visible: false

  property int refreshIntervalSec: 120
  property string availability: "checking"   // checking | ready | missing | malformed | failed
  property var providers: []
  property string statusError: ""      // last failed status run; cleared by the next good one
  property string actionError: ""      // last failed action; cleared by the next action or on close
  property string message: ""
  property bool statusPending: false
  property bool actionPending: false
  property bool refreshQueued: false
  property bool refreshQueuedForce: false
  property string statusOutput: ""
  property string statusProcessError: ""
  property string lastStatusText: ""
  property double lastStatusAtMs: 0
  property string actionOutput: ""
  property string actionProcessError: ""
  readonly property string error: statusError !== "" ? statusError : actionError
  readonly property bool refreshing: statusPending || statusProcess.running
  // Status takes no lock and only reads, so a refresh never blocks an action.
  readonly property bool busy: actionPending || actionProcess.running

  function providerTitle(id) {
    if (id === "claude") return "Claude Code"
    if (id === "codex") return "Codex"
    return String(id)
  }

  function elide(output, fallback) {
    var value = String(output || fallback || "").replace(/\s+/g, " ").trim()
    return value.length > 180 ? value.substring(0, 177) + "…" : value
  }

  function normalizeLive(live) {
    if (live === null) return null
    if (!live || typeof live.email !== "string") return undefined
    return { email: live.email, plan: String(live.plan || "") }
  }

  // The CLI's usage record: fetchedAt (epoch seconds), note, limits[]. A limit
  // is {label, percent (0-100), resetsAt (ISO or "")}.
  function normalizeUsage(usage) {
    if (usage === null || usage === undefined) return null
    if (!usage || !Array.isArray(usage.limits)) return undefined
    var limits = []
    for (var i = 0; i < usage.limits.length; i += 1) {
      var l = usage.limits[i]
      if (!l || typeof l.label !== "string") return undefined
      limits.push({ label: l.label, percent: Number(l.percent), resetsAt: String(l.resetsAt || "") })
    }
    return { fetchedAt: Number(usage.fetchedAt || 0), state: String(usage.state || "unknown"),
      note: String(usage.note || ""), limits: limits }
  }

  function normalize(content) {
    var value
    try { value = JSON.parse(String(content || "")) }
    catch (error) { return null }
    if (!value || !Array.isArray(value.providers)) return null
    var out = []
    for (var i = 0; i < value.providers.length; i += 1) {
      var p = value.providers[i]
      if (!p || typeof p.id !== "string" || !Array.isArray(p.accounts)) return null
      var live = normalizeLive(p.live)
      if (live === undefined) return null
      if (p.error !== undefined && typeof p.error !== "string") return null
      var accounts = []
      for (var j = 0; j < p.accounts.length; j += 1) {
        var a = p.accounts[j]
        if (!a || typeof a.email !== "string") return null
        var usage = normalizeUsage(a.usage)
        if (usage === undefined) return null
        accounts.push({ email: a.email, plan: String(a.plan || ""), active: a.active === true, usage: usage })
      }
      out.push({ id: p.id, title: providerTitle(p.id), live: live, accounts: accounts,
        error: String(p.error || "") })
    }
    return out
  }

  function refresh(force) {
    if (refreshing) { refreshQueued = true; refreshQueuedForce = refreshQueuedForce || !!force; return }
    var queuedForce = refreshQueuedForce
    refreshQueued = false
    refreshQueuedForce = false
    force = !!force || queuedForce
    if (!force && lastStatusAtMs > 0 && Date.now() - lastStatusAtMs < 5000) return
    statusOutput = ""
    statusProcessError = ""
    statusProcess.command = ["kiba", "status", "--json"]
    statusPending = true
    statusProcess.running = true
  }

  function runAction(label, command) {
    if (busy) return
    actionOutput = ""
    actionProcessError = ""
    message = label
    actionError = ""
    actionProcess.command = command
    actionPending = true
    actionProcess.running = true
  }

  function use(provider, email) {
    runAction("Switching " + providerTitle(provider) + " to " + email + "…",
      ["kiba", "use", provider, email])
  }

  function probeUsage() {
    runAction("Probing usage for every saved account…", ["kiba", "usage"])
  }

  // The newest usage record across every saved account; 0 when none exists.
  function newestUsageAt() {
    var newest = 0
    for (var i = 0; i < providers.length; i += 1)
      for (var j = 0; j < providers[i].accounts.length; j += 1) {
        var u = providers[i].accounts[j].usage
        if (u && u.fetchedAt > newest) newest = u.fetchedAt
      }
    return newest
  }

  function save(provider) {
    runAction("Saving the current " + providerTitle(provider) + " login…",
      ["kiba", "save", provider])
  }

  // Login needs a browser hand-off and a terminal prompt, so it runs in its own terminal.
  function add(provider) {
    Quickshell.execDetached([
      "xdg-terminal-exec", "--title=Kiba: add " + provider, "--hold", "--",
      "kiba", "add", provider
    ])
  }

  function statusStoppedWithoutExit() {
    if (!statusPending || statusProcess.running) return
    statusPending = false
    availability = "missing"
    providers = []
    statusError = "The kiba command did not run. Install it to ~/.local/bin with build.sh."
    if (refreshQueued) refresh()
  }

  function actionStoppedWithoutExit() {
    if (!actionPending || actionProcess.running) return
    actionPending = false
    message = ""
    actionError = "The kiba command did not run. Install it to ~/.local/bin with build.sh."
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: statusStdout
      waitForEnd: true
      onStreamFinished: root.statusOutput = text
    }
    stderr: StdioCollector {
      id: statusStderr
      waitForEnd: true
      onStreamFinished: root.statusProcessError = text
    }
    onExited: function(exitCode) {
      if (!root.statusPending) return
      root.statusPending = false
      var stdout = String(statusStdout.text || root.statusOutput || "")
      var stderr = String(statusStderr.text || root.statusProcessError || "")
      if (exitCode !== 0) {
        root.availability = "failed"
        root.providers = []
        root.statusError = root.elide(stderr || stdout, "kiba status failed.")
      } else {
        var next = root.normalize(stdout)
        if (next === null) {
          root.availability = "malformed"
          root.providers = []
          root.statusError = "kiba status returned unreadable JSON."
        } else {
          root.availability = "ready"
          root.lastStatusAtMs = Date.now()
          if (stdout !== root.lastStatusText) {
            root.lastStatusText = stdout
            root.providers = next
          }
          root.statusError = ""
        }
      }
      if (root.refreshQueued) root.refresh()
    }
    onRunningChanged: if (!running && root.statusPending) {
      Qt.callLater(function() { root.statusStoppedWithoutExit() })
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: actionStdout
      waitForEnd: true
      onStreamFinished: root.actionOutput = text
    }
    stderr: StdioCollector {
      id: actionStderr
      waitForEnd: true
      onStreamFinished: root.actionProcessError = text
    }
    onExited: function(exitCode) {
      if (!root.actionPending) return
      root.actionPending = false
      var stdout = String(actionStdout.text || root.actionOutput || "")
      var stderr = String(actionStderr.text || root.actionProcessError || "")
      if (exitCode === 0) {
        root.message = root.elide(stdout, "Done.")
        root.actionError = ""
        messageTimer.restart()
      } else {
        root.message = ""
        root.actionError = root.elide(stderr || stdout, "kiba failed.")
      }
      root.refresh(true)
    }
    onRunningChanged: if (!running && root.actionPending) {
      Qt.callLater(function() { root.actionStoppedWithoutExit() })
    }
  }

  Timer {
    id: messageTimer
    interval: 4000
    repeat: false
    onTriggered: root.message = ""
  }

  // Every status call pays the CLI's start-up cost, so the periodic refresh
  // runs only while the panel is open; opening it refreshes anyway.
  property bool panelOpen: false

  Timer {
    interval: Math.max(15, root.refreshIntervalSec) * 1000
    running: root.panelOpen
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: refresh()
}
