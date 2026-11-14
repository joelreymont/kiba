import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

// Bar widget: which saved account has room, and how much; one click
// switches to it through the kiba CLI. The row reading is kiba-mac's Rows.
Panel {
  id: root
  moduleName: "kiba"
  ipcTarget: "kiba"

  property string cursorKey: ""        // the control under the cursor; "" for none
  property int cursorIndex: 0          // its place, kept when the control goes
  property double nowMs: Date.now()
  property var confirming: null        // {kind: forget | reset, provider, name}
  property var menuAccount: null       // the row whose context menu is open: {provider, name}

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  // kiba-mac's green and amber, each in its light or dark theme shade
  readonly property bool lightTheme: Color.background.hslLightness > 0.5
  readonly property color good: lightTheme ? "#1f7f52" : "#4fc08a"
  readonly property color caution: lightTheme ? "#9e6a0e" : "#e2a93b"
  readonly property color track: alpha(foreground, 0.15)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var providers: status.providers
  readonly property bool alerting: status.error !== ""
  readonly property bool inactive: status.availability !== "ready"
  readonly property color stateColor: alerting ? urgent : (inactive ? dim : foreground)

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // ---------------------------------------------------------------- rows
  //
  // Only the session and the weekly window decide whether an account can
  // take work; a model's own window (Fable, Opus) bars only that model.
  readonly property string sessionLabel: "Session (5-hour)"
  readonly property string weeklyLabel: "Weekly (7-day)"

  // the window under `label` with a reading; -1 for none
  function windowAt(usage, label) {
    if (!usage) return -1
    for (var i = 0; i < usage.limits.length; i += 1)
      if (usage.limits[i].label === label && usage.limits[i].percent >= 0) return i
    return -1
  }

  function deciding(usage) {
    return [windowAt(usage, sessionLabel), windowAt(usage, weeklyLabel)].filter(function(i) { return i >= 0 })
  }

  function weekly(usage) {
    var w = windowAt(usage, weeklyLabel)
    return w >= 0 ? usage.limits[w] : null
  }

  // the window that decides the color: the session, else the week
  function headline(usage) {
    var s = windowAt(usage, sessionLabel)
    return s >= 0 ? usage.limits[s] : weekly(usage)
  }

  // `YYYY-MM-DDTHH:MM[:SS[.fraction]]` then `Z` or `±HH[[:]MM]`, as epoch
  // milliseconds; NaN for anything else, a missing zone included
  function parseISO(text) {
    var m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(\.\d+)?)?(?:(Z)|([+-])(\d{2})(?::?(\d{2}))?)$/
      .exec(String(text || ""))
    if (!m) return NaN
    var y = +m[1], mo = +m[2], d = +m[3], h = +m[4], mi = +m[5], sec = m[6] ? +m[6] : 0
    var zh = m[10] ? +m[10] : 0, zm = m[11] ? +m[11] : 0
    var days = [31, (y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0)) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    if (mo < 1 || mo > 12 || d < 1 || d > days[mo - 1] || h > 23 || mi > 59 || sec > 59 || zh > 23 || zm > 59) return NaN
    var off = m[8] ? 0 : (m[9] === "-" ? -1 : 1) * (zh * 60 + zm) * 60000
    return Date.UTC(y, mo - 1, d, h, mi, sec) + (m[7] ? parseFloat("0" + m[7]) * 1000 : 0) - off
  }

  // The used-up deciding window that reopens last; the first used-up one
  // when no later reset parses.
  function blocking(usage) {
    if (!usage) return null
    var worst = null, worstAt = NaN
    var d = deciding(usage)
    for (var i = 0; i < d.length; i += 1) {
      var l = usage.limits[d[i]]
      if (l.percent < 100) continue
      var at = parseISO(l.resetsAt)
      if (!worst) { worst = l; worstAt = at; continue }
      if (isFinite(at) && (!isFinite(worstAt) || at > worstAt)) { worst = l; worstAt = at }
    }
    return worst
  }

  // ok, tight, blocked (the session or the week used up), dead (the saved
  // login no longer works), unsubscribed (no plan the CLI may use), unknown
  function rowState(usage, active) {
    if (status.dead(usage, active)) return "dead"
    if (usage && (usage.state === "unsubscribed" || usage.state === "free")) return "unsubscribed"
    if (!usage || usage.limits.length === 0) return "unknown"
    if (blocking(usage)) return "blocked"
    var h = headline(usage)
    if (h && 100 - h.percent < 50) return "tight"
    var d = deciding(usage)
    for (var i = 0; i < usage.limits.length; i += 1)
      if (d.indexOf(i) < 0 && 100 - usage.limits[i].percent < 50) return "tight"
    return "ok"
  }

  // a model window, one that does not decide, is used up
  function modelOut(usage) {
    if (!usage) return false
    var d = deciding(usage)
    for (var i = 0; i < usage.limits.length; i += 1)
      if (d.indexOf(i) < 0 && usage.limits[i].percent >= 100) return true
    return false
  }

  // Room first, then running low, then a model window used up, then the
  // session used up, then the week, then dead or without a plan, then unknown.
  function rank(usage, active) {
    var s = rowState(usage, active)
    if (s === "ok") return 0
    if (s === "tight") return modelOut(usage) ? 2 : 1
    if (s === "blocked") { var w = weekly(usage); return w && w.percent >= 100 ? 4 : 3 }
    if (s === "dead" || s === "unsubscribed") return 5
    return 6
  }

  // by rank; limited rows by when they reopen, soonest first and the ones
  // with no parseable reset last; otherwise the CLI's order
  function sorted(accounts) {
    var keyed = accounts.map(function(a, i) {
      var r = rank(a.usage, a.active), at = Infinity
      if (r === 3 || r === 4) {
        var b = blocking(a.usage)
        var t = b ? parseISO(b.resetsAt) : NaN
        if (isFinite(t)) at = t
      }
      return { rank: r, at: at, idx: i, account: a }
    })
    keyed.sort(function(x, y) {
      if (x.rank !== y.rank) return x.rank - y.rank
      if (x.at !== y.at) return x.at < y.at ? -1 : 1
      return x.idx - y.idx
    })
    return keyed.map(function(k) { return k.account })
  }

  // Session, weekly, then every other window, each with the percent left
  // the CLI gives its figure (Claude's session reads 0 while its week is
  // used up).
  function figures(usage) {
    if (!usage) return []
    var s = windowAt(usage, sessionLabel), w = windowAt(usage, weeklyLabel)
    var order = []
    if (s >= 0) order.push(s)
    if (w >= 0) order.push(w)
    for (var i = 0; i < usage.limits.length; i += 1) if (i !== s && i !== w) order.push(i)
    var out = []
    for (var j = 0; j < order.length; j += 1) {
      var l = usage.limits[order[j]]
      if (l.left !== null) out.push({ label: l.label, left: l.left })
    }
    return out
  }

  function isLow(f) { return f.left < 50 }

  // the status dot's verdict: the account can take work; null while unknown
  function usable(state) {
    if (state === "ok" || state === "tight") return true
    if (state === "unknown") return null
    return false
  }

  // every bar segment an empty track: no window holds anything usable
  function drained(state) { return state === "dead" || state === "unsubscribed" }

  function figuresText(usage) {
    if (rowState(usage, false) === "blocked") return "limit"
    return figures(usage).map(function(f) { return f.left + "%" }).join(" · ")
  }

  // the token document still claims the plan the organization no longer has
  function planLabel(a) {
    if (a.usage && a.usage.state === "unsubscribed") return "no plan"
    if (a.usage && a.usage.state === "free") return "free"
    return a.plan
  }

  // "(pro)", "(pro, 5d)" while blocked, "(pro, log in again)" when dead,
  // "(no plan)", "(free)", or ""
  function planText(a) {
    var parts = []
    var label = planLabel(a)
    if (label !== "") parts.push(label)
    var b = blocking(a.usage)
    if (b) { var when = resetShort(b.resetsAt); if (when !== "") parts.push(when) }
    if (status.dead(a.usage, a.active)) parts.push("log in again")
    return parts.length > 0 ? "(" + parts.join(", ") + ")" : ""
  }

  function resetsText(n) { return n + (n === 1 ? " limit reset" : " limit resets") }

  function tooltipText(p, a) {
    var head = a.name
    var label = planLabel(a)
    if (label !== "") head += " · " + label
    if (a.active) head += " · current"
    var lines = [head]
    var u = a.usage
    if (u) {
      if (u.limits.length === 0) lines.push(u.note !== "" ? u.note : "No limits reported")
      else for (var i = 0; i < u.limits.length; i += 1) {
        var l = u.limits[i]
        var left = l.percent >= 100 ? "limit reached" : (100 - l.percent) + "% left"
        var when = l.resetsAt !== "" ? " · resets in " + resetLong(l.resetsAt) : ""
        lines.push(l.label + ": " + left + when)
      }
      if (u.resets > 0) lines.push(resetsText(u.resets) + " available")
      if (u.fetchedAt > 0) lines.push("Probed " + age(u.fetchedAt))
    } else lines.push("Usage not probed yet")
    if (status.relogin(u, a.active)) lines.push("Click to log in to this account again")
    else if (!a.active) lines.push("Click to switch " + p.title + " to this account")
    return lines.join("\n")
  }

  function minutesTo(at) { return Math.max(0, Math.round((at - nowMs) / 60000)) }

  // "20m", "5h" under 36 hours, else "2d"; "" when unparseable
  function resetShort(iso) {
    var at = parseISO(iso)
    if (!isFinite(at)) return ""
    var min = minutesTo(at)
    if (min < 60) return min + "m"
    var h = Math.round(min / 60)
    if (h < 36) return h + "h"
    return Math.round(h / 24) + "d"
  }

  // "20 min", "5 h 12 min" under 48 hours, else "3 days"; "" when unparseable
  function resetLong(iso) {
    var at = parseISO(iso)
    if (!isFinite(at)) return ""
    var min = minutesTo(at)
    if (min < 60) return min + " min"
    var h = Math.floor(min / 60)
    if (h < 48) return h + " h " + (min % 60) + " min"
    return Math.round(h / 24) + " days"
  }

  function age(epoch) {
    var min = Math.max(0, Math.round((nowMs / 1000 - epoch) / 60))
    return min < 1 ? "just now" : min + " min ago"
  }

  // ---------------------------------------------------------------- panel
  // the providers as the panel shows them; a live login that is readable
  // and not saved can be saved
  readonly property var view: providers.map(function(p) {
    return { id: p.id, title: p.title, live: p.live, error: p.error, accounts: sorted(p.accounts),
      canSave: !!p.live && p.error === "" && !p.accounts.some(function(a) { return a.active }) }
  })

  // header meta: the latest probe's age and whether it reached every
  // account; before any probe, the age of the oldest record shown
  readonly property string meta: {
    if (status.busy) return "Working…"
    if (status.refreshing) return "Refreshing…"
    if (status.availability !== "ready") return "Unavailable"
    if (status.lastProbe) return (status.probeComplete ? "All usage probed " : "Some usage probed ") + age(status.lastProbe.at)
    var oldest = status.oldestUsageAt()
    return oldest > 0 ? "Oldest usage from " + age(oldest) : "Saved logins"
  }

  readonly property string probeAge: status.lastProbe ? age(status.lastProbe.at) : ""

  function tooltip() {
    if (status.availability !== "ready") return "AI accounts"
    return providers.map(function(p) { return p.title + ": " + (p.live ? p.live.email : "none") }).join("\n")
  }

  // ---------------------------------------------------------------- gauge
  readonly property var gaugeProviders: ["claude", "codex"]
  // a failed status read or action paints every cell, in the urgent color
  readonly property bool gaugeAlert: status.statusError !== "" || status.actionError !== ""

  // a provider's own failure, from the status read or its latest probe,
  // paints its cell
  readonly property var gauge: gaugeProviders.map(function(id) {
    var p = null
    for (var i = 0; i < providers.length; i += 1) if (providers[i].id === id) p = providers[i]
    if (gaugeAlert || (p && p.error !== "") || status.probeFault(id)) return { kind: "fault", left: 0 }
    return gaugeCell(p)
  })

  // the current account's headline room; spent when nothing usable is left
  function gaugeCell(p) {
    var a = p ? p.accounts.find(function(x) { return x.active }) : undefined
    if (!a) return { kind: "unknown", left: 0 }
    var s = rowState(a.usage, true)
    if (s === "blocked" || s === "dead" || s === "unsubscribed") return { kind: "spent", left: 0 }
    var h = s === "unknown" ? null : headline(a.usage)
    if (!h) return { kind: "unknown", left: 0 }
    return { kind: "level", left: Math.max(0, Math.min(100, 100 - h.percent)) }
  }

  // ---------------------------------------------------------------- cursor
  function keyOf(kind, provider, name) { return kind + "\n" + provider + "\n" + name }

  function mk(kind, provider, name) {
    return { kind: kind, provider: provider, name: name, key: keyOf(kind, provider, name) }
  }

  function confirmingRow(provider, name) {
    return !!confirming && confirming.provider === provider && confirming.name === name
  }

  // Every control a click can reach, in panel order: Dismiss, Retry, then
  // per provider its add, each account row followed by its log-in-again
  // and limit-reset badges, and its save; Refresh usage last. A confirming
  // row offers its go and Keep buttons instead of the row and its badges.
  readonly property var actions: {
    var out = []
    if (status.canDismiss) out.push(mk("dismiss", "", ""))
    if (status.canRetry) out.push(mk("retry", "", ""))
    for (var i = 0; i < view.length; i += 1) {
      var p = view[i]
      out.push(mk("add", p.id, ""))
      for (var j = 0; j < p.accounts.length; j += 1) {
        var a = p.accounts[j]
        if (confirmingRow(p.id, a.name)) {
          out.push(mk("confirm", p.id, a.name))
          out.push(mk("keep", p.id, a.name))
        } else {
          out.push(mk("use", p.id, a.name))
          if (status.relogin(a.usage, a.active)) out.push(mk("relogin", p.id, a.name))
          if (a.usage && a.usage.resets > 0) out.push(mk("redeem", p.id, a.name))
        }
      }
      if (p.canSave) out.push(mk("save", p.id, ""))
    }
    if (view.length > 0) out.push(mk("usage", "", ""))
    return out
  }

  function indexOfKey(key) {
    for (var i = 0; i < actions.length; i += 1) if (actions[i].key === key) return i
    return -1
  }

  // the cursor tracks its control across refreshes and stays at the same
  // place when the control is gone
  onActionsChanged: {
    if (cursorKey === "") return
    var i = indexOfKey(cursorKey)
    if (i >= 0) { cursorIndex = i; return }
    if (actions.length === 0) { cursorKey = ""; return }
    cursorIndex = Math.min(cursorIndex, actions.length - 1)
    cursorKey = actions[cursorIndex].key
  }

  // hover moves the cursor without scrolling
  function pointKey(key) {
    var i = indexOfKey(key)
    if (i < 0) return
    cursorKey = key
    cursorIndex = i
  }

  function itemFor(a) {
    if (a.kind === "dismiss") return dismissButton
    if (a.kind === "retry") return retryRow
    if (a.kind === "usage") return usageRow
    for (var i = 0; i < view.length; i += 1) {
      if (view[i].id !== a.provider) continue
      var block = providerRepeater.itemAt(i)
      if (!block) return null
      if (a.kind === "add") return block.addItem
      if (a.kind === "save") return block.saveItem
      for (var j = 0; j < view[i].accounts.length; j += 1)
        if (view[i].accounts[j].name === a.name) return block.accountRows.itemAt(j)
    }
    return null
  }

  function scrollIntoView(item) {
    if (!item) return
    Qt.callLater(function() {
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var maximum = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > panelFlick.contentY + panelFlick.height - margin)
        panelFlick.contentY = Math.min(maximum, bottom + margin - panelFlick.height)
    })
  }

  // the keyboard moves one control and scrolls it into view; the first
  // move lands on the first control, or the last going up
  function moveCursor(dx, dy) {
    var delta = dy !== 0 ? dy : dx
    if (delta === 0 || actions.length === 0) return
    var i = indexOfKey(cursorKey)
    var next = i < 0 ? (delta < 0 ? actions.length - 1 : 0)
      : Math.max(0, Math.min(actions.length - 1, i + (delta > 0 ? 1 : -1)))
    cursorKey = actions[next].key
    cursorIndex = next
    scrollIntoView(itemFor(actions[next]))
  }

  // Each action refuses while one runs, but a row click during a probe
  // queues; Keep, Dismiss and Retry always run.
  function trigger(a) {
    if (a.kind === "use") status.use(a.provider, a.name)
    else if (a.kind === "relogin") status.logInAgain(a.provider, a.name)
    else if (a.kind === "redeem") ask("reset", a.provider, a.name)
    else if (a.kind === "save") status.save(a.provider)
    else if (a.kind === "add") status.add(a.provider, "")
    else if (a.kind === "confirm") confirm()
    else if (a.kind === "keep") keep()
    else if (a.kind === "retry") status.refresh(true)
    else if (a.kind === "dismiss") status.dismiss()
    else if (a.kind === "usage") status.probeUsage()
  }

  function activate() {
    var i = indexOfKey(cursorKey)
    if (i >= 0) trigger(actions[i])
  }

  // a confirmation stands while its row exists and, for a reset, still offers one
  function stands(c) {
    var a = status.account(c.provider, c.name)
    if (!a) return false
    return c.kind === "forget" || (!!a.usage && a.usage.resets > 0)
  }

  // turns the row into its confirmation, the cursor on Keep
  function ask(kind, provider, name) {
    var c = { kind: kind, provider: provider, name: name }
    if (status.busy || !stands(c)) return
    confirming = c
    pointKey(keyOf("keep", provider, name))
  }

  // ends the confirmation; a cursor on its buttons returns to the control that asked
  function keep() {
    var c = confirming
    if (!c) return
    if (cursorKey === keyOf("confirm", c.provider, c.name) || cursorKey === keyOf("keep", c.provider, c.name))
      cursorKey = keyOf(c.kind === "reset" ? "redeem" : "use", c.provider, c.name)
    confirming = null
  }

  function confirm() {
    var c = confirming
    if (!c || status.busy) return
    keep()
    if (c.kind === "forget") status.forget(c.provider, c.name)
    else status.redeem(c.provider, c.name)
  }

  function backOut() {
    if (confirming) keep()
    else root.close()
  }

  // Delete (or x) on an account row asks to forget it
  function forgetCursor() {
    var i = indexOfKey(cursorKey)
    if (i >= 0 && actions[i].kind === "use") ask("forget", actions[i].provider, actions[i].name)
  }

  // Ctrl+L on an account row but the live one logs in to it again
  function reloginCursor() {
    var i = indexOfKey(cursorKey)
    if (i >= 0 && actions[i].kind === "use") status.logInAgain(actions[i].provider, actions[i].name)
  }

  function openMenu(item, x, y, provider, a) {
    menuAccount = { provider: provider, name: a.name }
    rowMenu.popup(item, x, y)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onOpenedChanged: {
    if (!opened) { keep(); status.closed(); return }
    cursorKey = ""
    cursorIndex = 0
    confirming = null
    panelFlick.contentY = 0
    nowMs = Date.now()
    status.opened()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Status {
    id: status
    refreshIntervalSec: Number(root.setting("refreshIntervalSec", 120))
  }

  Connections {
    target: status
    function onProvidersChanged() { if (root.confirming && !root.stands(root.confirming)) root.confirming = null }
    function onCloseRequested() { root.close() }
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        Gauge {
          x: (parent.width - width) / 2
          y: (parent.height - height) / 2
          cells: root.gauge
          ink: root.gaugeAlert ? root.urgent : root.foreground
          opacity: root.inactive ? 0.5 : 1
        }
      }
    }
    tooltipText: root.tooltip()
    // a right click refreshes usage without opening the panel, as the
    // shell's own panels give a right click a direct action
    onPressed: function(buttonCode) {
      if (buttonCode !== Qt.RightButton) root.toggle()
      else if (status.availability === "ready") status.probeUsage()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activate()
      onCloseRequested: root.backOut()
      onDeleteRequested: root.forgetCursor()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text, modifiers) {
        if ((modifiers & Qt.ControlModifier) && (text === "\u000c" || text === "l" || text === "L")) root.reloginCursor()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

        Column {
          id: content
          width: panelFlick.width
          spacing: Style.space(6)

          PanelHero {
            width: parent.width
            title: "Room to work"
            meta: root.meta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.inactive ? 0.55 : 1
            iconComponent: Component {
              Text {
                text: "󰀙"
                color: root.stateColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          // the error, the held result and the passing message, each shown
          // whole; Dismiss at the right while a result or an action error is held
          Item {
            visible: status.error !== "" || status.note !== "" || status.message !== ""
            width: parent.width
            implicitHeight: Math.max(notices.implicitHeight, dismissButton.visible ? dismissButton.height : 0)

            Column {
              id: notices
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.right: dismissButton.visible ? dismissButton.left : parent.right
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(6)

              Repeater {
                model: [
                  { text: status.error, color: root.urgent },
                  { text: status.note, color: root.foreground },
                  { text: status.message, color: root.dim }
                ]
                delegate: Text {
                  required property var modelData
                  visible: modelData.text !== ""
                  width: notices.width
                  text: modelData.text
                  color: modelData.color
                  textFormat: Text.PlainText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }
              }
            }

            // only clears what is shown, so it stays live while an action runs
            Item {
              id: dismissButton
              visible: status.canDismiss
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.top: parent.top
              width: dismissGlyph.implicitWidth + Style.space(8)
              height: dismissGlyph.implicitHeight + Style.space(4)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: root.alpha(root.foreground, root.cursorKey === root.keyOf("dismiss", "", "") ? 0.10 : 0)
              }

              Text {
                id: dismissGlyph
                anchors.centerIn: parent
                text: "✕"
                color: root.cursorKey === root.keyOf("dismiss", "", "") ? Color.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: dismissMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) root.pointKey(root.keyOf("dismiss", "", ""))
                onClicked: status.dismiss()
              }

              PanelToolTip {
                visible: dismissMouse.containsMouse
                text: "Dismiss notice"
                fontFamily: root.fontFamily
              }
            }
          }

          ActionRow {
            id: retryRow
            visible: status.canRetry
            actionKey: root.keyOf("retry", "", "")
            label: "Retry"
            onActivated: status.refresh(true)
          }

          PanelSeparator { visible: root.view.length > 0; foreground: root.foreground }

          Repeater {
            id: providerRepeater
            model: root.view

            delegate: Column {
              id: providerBlock
              required property var modelData
              readonly property alias accountRows: accountRepeater
              readonly property alias saveItem: saveAction
              readonly property alias addItem: addButton
              width: content.width
              spacing: Style.space(2)

              // the section header with the add action at its right
              Item {
                width: parent.width
                height: Math.max(sectionTitle.implicitHeight, addButton.height) + Style.space(4)

                Text {
                  id: sectionTitle
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: providerBlock.modelData.title
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Item {
                  id: addButton
                  readonly property string key: root.keyOf("add", providerBlock.modelData.id, "")
                  readonly property string label: "Add " + providerBlock.modelData.title + " account"
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  width: addGlyph.implicitWidth + Style.space(12)
                  height: addGlyph.implicitHeight + Style.space(2)

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.cornerRadius
                    color: root.alpha(root.foreground, root.cursorKey === addButton.key ? 0.10 : 0)
                  }

                  Text {
                    id: addGlyph
                    anchors.centerIn: parent
                    text: "+"
                    color: root.cursorKey === addButton.key ? Color.accent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }

                  MouseArea {
                    id: addMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: status.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) root.pointKey(addButton.key)
                    onClicked: status.add(providerBlock.modelData.id, "")
                  }

                  PanelToolTip {
                    visible: addMouse.containsMouse
                    text: addButton.label
                    fontFamily: root.fontFamily
                  }
                }
              }

              Text {
                visible: providerBlock.modelData.error !== "" || !providerBlock.modelData.live
                width: parent.width
                leftPadding: Style.space(10)
                rightPadding: Style.space(10)
                text: providerBlock.modelData.error !== "" ? providerBlock.modelData.error : "Not logged in"
                textFormat: Text.PlainText
                color: providerBlock.modelData.error !== "" ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
              }

              Repeater {
                id: accountRepeater
                model: providerBlock.modelData.accounts

                delegate: AccountRow {
                  required property var modelData
                  provider: providerBlock.modelData
                  account: modelData
                }
              }

              ActionRow {
                id: saveAction
                visible: providerBlock.modelData.canSave
                actionKey: root.keyOf("save", providerBlock.modelData.id, "")
                label: "Save the current login"
                onActivated: status.save(providerBlock.modelData.id)
              }
            }
          }

          PanelSeparator { visible: root.view.length > 0; foreground: root.foreground }

          ActionRow {
            id: usageRow
            visible: root.view.length > 0
            actionKey: root.keyOf("usage", "", "")
            label: "Refresh usage"
            detail: root.probeAge
            onActivated: status.probeUsage()
          }
        }
      }

      // the account row's context menu: Forget…
      Controls.Menu {
        id: rowMenu
        onClosed: keyCatcher.forceActiveFocus()

        background: Rectangle {
          implicitWidth: Style.space(180)
          color: Color.menu.background
          border.color: Color.menu.border
          border.width: 1
          radius: Style.cornerRadius
        }

        MenuEntry {
          enabled: !status.busy
          text: "Forget…"
          onTriggered: root.ask("forget", root.menuAccount.provider, root.menuAccount.name)
        }
      }
    }
  }

  component MenuEntry: Controls.MenuItem {
    id: entry
    height: visible ? implicitHeight : 0
    contentItem: Text {
      text: entry.text
      color: !entry.enabled ? root.dim : (entry.highlighted ? Color.menu.selectedText : Color.menu.text)
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.bodySmall
      leftPadding: Style.space(6)
    }
    background: Rectangle {
      radius: Style.cornerRadius
      color: entry.highlighted ? Color.menu.selectedBackground : "transparent"
    }
  }

  // The bar under a row: one segment per figure, filled from the left to
  // the share of its window left, green with half or more, amber under
  // half, on a grey track; drained, every segment is an empty track, and a
  // row with no figures shows the session and the week as empty tracks.
  component Reservoir: Item {
    id: reservoir
    property var figures: []
    property bool drained: false
    readonly property int count: figures.length > 0 ? figures.length : 2
    readonly property real gap: Style.space(3)
    height: Style.space(4)

    Row {
      spacing: reservoir.gap

      Repeater {
        model: reservoir.count

        delegate: Rectangle {
          required property int index
          readonly property var figure: reservoir.figures.length > 0 ? reservoir.figures[index] : null
          readonly property real fraction: !figure || reservoir.drained ? 0 : Math.min(Math.max(figure.left / 100, 0), 1)
          width: (reservoir.width - reservoir.gap * (reservoir.count - 1)) / reservoir.count
          height: reservoir.height
          radius: Style.space(2)
          color: root.track

          // a remainder too thin to see still shows a sliver as wide as the bar is tall
          Rectangle {
            height: parent.height
            width: parent.fraction > 0 ? Math.max(parent.width * parent.fraction, parent.height) : 0
            visible: width > 0
            radius: Math.min(Style.space(2), width / 2)
            color: parent.figure && root.isLow(parent.figure) ? root.caution : root.good
            Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
          }
        }
      }
    }
  }

  // A saved account: dot, name, plan, figures, its log-in-again badge and
  // its limit-reset badge, the reservoir below. No box: the row lights
  // under the pointer or the keyboard cursor, and faintly while it is the
  // live login. A confirming row shows its question with its go and Keep
  // buttons instead.
  component AccountRow: Item {
    id: row
    required property var provider
    required property var account
    readonly property string key: root.keyOf("use", provider.id, account.name)
    readonly property bool asking: root.confirmingRow(provider.id, account.name)
    readonly property string standing: root.rowState(account.usage, account.active)
    readonly property bool red: root.usable(standing) === false
    readonly property int offer: account.usage ? account.usage.resets : 0
    readonly property bool relogin: status.relogin(account.usage, account.active)
    // account rows stay live during a probe and queue their action
    readonly property bool live: !(status.busy && !status.probing)
    readonly property real inset: Style.space(10)
    readonly property real badgeGap: Style.space(6)
    // the badges' span at the line's end, the gap between them included
    readonly property real badgesWidth: (relogin ? reloginBadge.width : 0) + (offer > 0 ? resetBadge.width : 0)
      + (relogin && offer > 0 ? badgeGap : 0)
    readonly property bool overBadge: reloginBadge.hovered || resetBadge.hovered

    width: parent.width
    implicitHeight: (asking ? askLine.height : nameLine.height + Style.space(5) + reservoirBar.height) + Style.space(12)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, root.cursorKey === row.key ? 0.10 : (row.account.active ? 0.05 : 0))
    }

    Item {
      id: nameLine
      visible: !row.asking
      anchors.left: parent.left
      anchors.leftMargin: row.inset
      anchors.right: parent.right
      anchors.rightMargin: row.inset
      anchors.top: parent.top
      anchors.topMargin: Style.space(6)
      height: Math.max(nameText.implicitHeight, row.badgesWidth > 0 ? resetBadge.height : 0)
      // The figures and the badges always fit; the name and the plan share
      // what they leave, each shortened in the middle so both ends still
      // read. A plan is the provider's word for it, an open set (Codex's
      // `self_serve_business_prolite`), so it keeps its full width only
      // while the name keeps half the room; the name, likewise. The name
      // is laid out at its shortened width, so the plan follows it closely.
      readonly property real gap: Style.space(8)
      readonly property real room: Math.max(0, figureText.x - nameText.x - gap - (planText.text !== "" ? gap : 0))
      readonly property real planWidth: Math.min(planText.implicitWidth,
        Math.max(room - nameFull.advanceWidth, room / 2))

      // the whole name's width apart from the shortened one: one metrics
      // object signals every width when its elide width moves
      TextMetrics {
        id: nameFull
        font: nameText.font
        text: row.account.name
      }

      TextMetrics {
        id: nameFit
        font: nameText.font
        text: row.account.name
        elide: Qt.ElideMiddle
        elideWidth: Math.max(0, nameLine.room - nameLine.planWidth)
      }

      Rectangle {
        id: dot
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(8)
        height: width
        radius: width / 2
        readonly property var verdict: root.usable(row.standing)
        color: verdict === true ? root.good : (verdict === false ? root.urgent : root.dim)
        opacity: verdict === null ? 0.6 : 1
      }

      Text {
        id: nameText
        anchors.left: dot.right
        anchors.leftMargin: nameLine.gap
        anchors.verticalCenter: parent.verticalCenter
        text: nameFit.elidedText
        textFormat: Text.PlainText
        color: row.account.active ? Color.accent : (row.red ? root.dim : root.foreground)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: row.account.active
      }

      Text {
        id: planText
        anchors.left: nameText.right
        anchors.leftMargin: nameLine.gap
        anchors.verticalCenter: parent.verticalCenter
        width: nameLine.planWidth
        text: root.planText(row.account)
        textFormat: Text.PlainText
        color: row.red ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideMiddle
      }

      Text {
        id: figureText
        anchors.right: parent.right
        anchors.rightMargin: row.badgesWidth > 0 ? row.badgesWidth + nameLine.gap : 0
        anchors.verticalCenter: parent.verticalCenter
        text: root.figuresText(row.account.usage)
        textFormat: Text.PlainText
        color: row.red ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.features: ({ "tnum": 1 })
      }
    }

    Reservoir {
      id: reservoirBar
      visible: !row.asking
      anchors.left: parent.left
      anchors.leftMargin: row.inset
      anchors.right: parent.right
      anchors.rightMargin: row.inset
      anchors.top: nameLine.bottom
      anchors.topMargin: Style.space(5)
      figures: root.figures(row.account.usage)
      drained: root.drained(row.standing)
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      enabled: !row.asking
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: row.live && !row.account.active ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: if (containsMouse && !row.overBadge) root.pointKey(row.key)
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) root.openMenu(rowMouse, mouse.x, mouse.y, row.provider.id, row.account)
        else if (row.live) status.use(row.provider.id, row.account.name)
      }

      // A login that no longer works, or whose usage checks are rate
      // limited: a click logs in to the account again, as a click on the row does.
      Badge {
        id: reloginBadge
        visible: row.relogin && !row.asking
        x: (row.offer > 0 ? resetBadge.x - row.badgeGap : row.width - row.inset) - width
        y: nameLine.y + (nameLine.height - height) / 2
        color: root.urgent
        key: root.keyOf("relogin", row.provider.id, row.account.name)
        label: "!"
        live: row.live
        tip: (status.dead(row.account.usage, row.account.active) ? "This login no longer works."
          : "Usage checks are rate limited.") + " Click to log in again."
        onActivated: status.logInAgain(row.provider.id, row.account.name)
        onHoverEnded: if (rowMouse.containsMouse && !row.overBadge) root.pointKey(row.key)
      }

      // The count of limit resets on offer; a click asks before spending one.
      Badge {
        id: resetBadge
        visible: row.offer > 0 && !row.asking
        x: row.width - row.inset - width
        y: nameLine.y + (nameLine.height - height) / 2
        color: Color.accent
        key: root.keyOf("redeem", row.provider.id, row.account.name)
        label: String(row.offer)
        live: !status.busy
        tip: root.resetsText(row.offer) + " available. Click to use one."
        onActivated: root.ask("reset", row.provider.id, row.account.name)
        onHoverEnded: if (rowMouse.containsMouse && !row.overBadge) root.pointKey(row.key)
      }
    }

    PanelToolTip {
      visible: rowMouse.containsMouse && !row.overBadge && !row.asking
      text: root.tooltipText(row.provider, row.account)
      fontFamily: root.fontFamily
    }

    // "Forget …? Forget / Keep" or "Use a limit reset on …? (2 left) Reset / Keep"
    Item {
      id: askLine
      visible: row.asking
      anchors.left: parent.left
      anchors.leftMargin: row.inset
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.top: parent.top
      anchors.topMargin: Style.space(6)
      height: Math.max(askText.implicitHeight, goButton.height)
      readonly property bool reset: !!root.confirming && root.confirming.kind === "reset"

      Text {
        id: askText
        anchors.left: parent.left
        anchors.right: goButton.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        // the name, shortened in its middle to fit one line with the tail,
        // so the question takes at most two lines and keeps both ends
        text: (askLine.reset ? "Use a limit reset on " : "Forget ") + askName.elidedText + askTail.text
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }

      TextMetrics {
        id: askTail
        font: askText.font
        text: askLine.reset ? "? (" + row.offer + " left)" : "?"
      }

      TextMetrics {
        id: askName
        font: askText.font
        text: row.account.name
        elide: Qt.ElideMiddle
        elideWidth: Math.max(0, askText.width - askTail.advanceWidth - Style.space(2))
      }

      ChoiceButton {
        id: goButton
        anchors.right: keepButton.left
        anchors.verticalCenter: parent.verticalCenter
        key: root.keyOf("confirm", row.provider.id, row.account.name)
        label: askLine.reset ? "Reset" : "Forget"
        tint: askLine.reset ? Color.accent : root.urgent
        bold: true
        enabled: !status.busy
        onActivated: root.confirm()
      }

      ChoiceButton {
        id: keepButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        key: root.keyOf("keep", row.provider.id, row.account.name)
        label: "Keep"
        tint: Color.accent
        onActivated: root.keep()
      }
    }
  }

  // A control of its own laid over an account row's name line, not inside
  // the row's button: its glyph on a capsule, a circle for one character.
  // Under the cursor it wears a ring clear of it, so the ring never crowds
  // the glyph, and the row does not light.
  component Badge: Rectangle {
    id: badge
    property string key: ""
    property string label: ""
    property string tip: ""
    property bool live: true
    readonly property alias hovered: badgeMouse.containsMouse
    signal activated()
    signal hoverEnded()
    height: Style.space(18)
    width: Math.max(height, badgeText.implicitWidth + Style.space(10))
    radius: height / 2

    Rectangle {
      visible: root.cursorKey === badge.key
      anchors.fill: parent
      anchors.margins: -(Style.spaceReal(2) + Style.spaceReal(1.5))
      radius: height / 2
      color: "transparent"
      border.width: Style.spaceReal(2)
      border.color: root.foreground
      antialiasing: true
    }

    Text {
      id: badgeText
      anchors.centerIn: parent
      text: badge.label
      color: Color.background
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    MouseArea {
      id: badgeMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: badge.live ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: {
        if (containsMouse) root.pointKey(badge.key)
        else badge.hoverEnded()
      }
      onClicked: badge.activated()
    }

    PanelToolTip {
      visible: badgeMouse.containsMouse
      text: badge.tip
      fontFamily: root.fontFamily
    }
  }

  // a confirmation's button, lit with the row fill under the cursor
  component ChoiceButton: Item {
    id: choice
    property string key: ""
    property string label: ""
    property color tint: root.foreground
    property bool bold: false
    signal activated()
    width: choiceText.implicitWidth + Style.space(12)
    height: choiceText.implicitHeight + Style.space(4)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, root.cursorKey === choice.key ? 0.10 : 0)
    }

    Text {
      id: choiceText
      anchors.centerIn: parent
      text: choice.label
      color: choice.enabled ? choice.tint : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: choice.bold
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: choice.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: if (containsMouse) root.pointKey(choice.key)
      onClicked: if (choice.enabled) choice.activated()
    }
  }

  // A flat command line ("Save the current login") with the rows' cursor fill.
  component ActionRow: Item {
    id: action
    property string label: ""
    property string detail: ""
    property string actionKey: ""
    signal activated()

    width: parent.width
    implicitHeight: actionLabel.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, root.cursorKey === action.actionKey ? 0.10 : 0)
    }

    Text {
      id: actionLabel
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.right: actionDetail.left
      anchors.verticalCenter: parent.verticalCenter
      text: action.label
      color: status.busy ? root.dim : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Text {
      id: actionDetail
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: action.detail
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: status.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) root.pointKey(action.actionKey)
      onClicked: if (!status.busy) action.activated()
    }
  }
}
