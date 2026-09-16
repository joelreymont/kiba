import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

// Bar widget: the live account per provider, every saved login with how much
// room it has left, and one-click switching through the kiba CLI.
Panel {
  id: root
  moduleName: "kiba"
  ipcTarget: "kiba"

  property bool cursorActive: false
  property int cursor: 0
  property string cursorKey: ""
  property double nowMs: Date.now()
  property bool autoProbed: false     // one probe per open

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color good: "#7bb36f"
  readonly property color caution: "#d3a24a"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var providers: status.providers
  readonly property bool alerting: status.error !== ""
  readonly property bool inactive: status.availability !== "ready"
  readonly property bool failed: status.availability === "failed" || status.availability === "malformed"
    || status.availability === "missing"
  readonly property color stateColor: alerting ? urgent : (inactive ? dim : foreground)

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // Rows are ordered by what they tell you: accounts with room first, then
  // the ones running low, then the used-up or dead ones, then the unknown.
  // Within a color the CLI's order (by name) is kept.
  function stateRank(state) {
    if (state === "ok") return 0
    if (state === "tight") return 1
    if (state === "blocked" || state === "dead") return 2
    return 3
  }

  function sortedAccounts(p) {
    var out = p.accounts.slice()
    out.sort(function(a, b) {
      var d = stateRank(usageState(a.usage, a.active)) - stateRank(usageState(b.usage, b.active))
      return d !== 0 ? d : p.accounts.indexOf(a) - p.accounts.indexOf(b)
    })
    return out
  }

  // the providers as the panel shows them
  readonly property var view: providers.map(function(p) {
    return { id: p.id, title: p.title, live: p.live, error: p.error, accounts: sortedAccounts(p) }
  })

  // One flat cursor over every row that can be activated, in panel order.
  readonly property var actions: {
    var out = []
    for (var i = 0; i < view.length; i += 1) {
      var p = view[i]
      for (var j = 0; j < p.accounts.length; j += 1)
        out.push({ kind: "use", provider: p.id, email: p.accounts[j].email, active: p.accounts[j].active })
      if (p.live && p.error === "" && !liveSaved(p)) out.push({ kind: "save", provider: p.id })
      out.push({ kind: "add", provider: p.id })
    }
    if (providers.length > 0) out.push({ kind: "usage", provider: "" })
    return out
  }

  // the CLI marks the live login's own slot active; no active row means the
  // live login is not saved, whatever its email
  function liveSaved(p) {
    for (var j = 0; j < p.accounts.length; j += 1)
      if (p.accounts[j].active) return true
    return false
  }

  function tooltip() {
    if (status.availability !== "ready") return "AI accounts"
    var parts = []
    for (var i = 0; i < providers.length; i += 1)
      parts.push(providers[i].title + ": " + (providers[i].live ? providers[i].live.email : "none"))
    return parts.join("\n")
  }

  // ---------------------------------------------------------------- usage
  //
  // The CLI names windows "Session (5-hour)" and "Weekly (7-day)"; a short
  // window is the session, anything weekly or monthly is the long one.
  function windowIsLong(label) {
    var t = String(label || "").toLowerCase()
    return t.indexOf("week") >= 0 || t.indexOf("7-day") >= 0 || t.indexOf("month") >= 0 || t.indexOf("30-day") >= 0
  }

  function sessionLimit(usage) {
    if (!usage) return null
    for (var i = 0; i < usage.limits.length; i += 1)
      if (!windowIsLong(usage.limits[i].label) && usage.limits[i].percent >= 0) return usage.limits[i]
    return null
  }

  function weeklyLimit(usage) {
    if (!usage) return null
    for (var i = 0; i < usage.limits.length; i += 1)
      if (windowIsLong(usage.limits[i].label) && usage.limits[i].percent >= 0) return usage.limits[i]
    return null
  }

  // The window that blocks the account: the exhausted one that resets last.
  function blockingLimit(usage) {
    if (!usage) return null
    var worst = null
    for (var i = 0; i < usage.limits.length; i += 1) {
      var l = usage.limits[i]
      if (l.percent < 100) continue
      var t = Date.parse(l.resetsAt)
      var w = worst ? Date.parse(worst.resetsAt) : NaN
      if (!worst || (isFinite(t) && (!isFinite(w) || t > w))) worst = l
    }
    return worst
  }

  // A saved login that no longer works: the CLI says so through the usage
  // state. An expired token on the live account is the CLI's to refresh.
  function loginDead(usage, active) {
    if (!usage) return false
    if (usage.state === "revoked") return true
    return usage.state === "expired" && !active
  }

  // The window that decides the color: the session when there is one, else
  // the only window reported.
  function headlineLimit(usage) {
    var s = sessionLimit(usage)
    return s ? s : weeklyLimit(usage)
  }

  // blocked: a window is used up; dead: the login no longer works; tight:
  // under half of the session left; ok: at least half left; unknown: no data
  function usageState(usage, active) {
    if (loginDead(usage, active)) return "dead"
    if (!usage || usage.limits.length === 0) return "unknown"
    for (var i = 0; i < usage.limits.length; i += 1)
      if (usage.limits[i].percent >= 100) return "blocked"
    var h = headlineLimit(usage)
    if (h && 100 - h.percent < 50) return "tight"
    for (var j = 0; j < usage.limits.length; j += 1)
      if (windowIsLong(usage.limits[j].label) && usage.limits[j] !== weeklyLimit(usage) && 100 - usage.limits[j].percent < 50) return "tight"
    return "ok"
  }

  function colorFor(state) {
    if (state === "blocked" || state === "dead") return urgent
    if (state === "tight") return caution
    if (state === "ok") return good
    return dim
  }

  // "1d", "5h", "20m": how long until a window opens again
  function resetShort(resetsAt) {
    var t = Date.parse(String(resetsAt || ""))
    if (!isFinite(t)) return ""
    var min = Math.max(0, Math.round((t - nowMs) / 60000))
    if (min < 60) return min + "m"
    var h = Math.round(min / 60)
    if (h < 36) return h + "h"
    return Math.round(h / 24) + "d"
  }

  function resetLong(resetsAt) {
    var t = Date.parse(String(resetsAt || ""))
    if (!isFinite(t)) return ""
    var min = Math.max(0, Math.round((t - nowMs) / 60000))
    if (min < 60) return min + " min"
    var h = Math.floor(min / 60)
    if (h < 48) return h + " h " + (min % 60) + " min"
    return Math.round(h / 24) + " days"
  }

  // "(pro)" normally; "(pro, 1d)" while a window blocks the account;
  // "(pro, add again)" when the saved login is dead
  function planText(account) {
    var parts = []
    if (account.plan !== "") parts.push(account.plan)
    var b = blockingLimit(account.usage)
    if (b && b.resetsAt !== "") parts.push(resetShort(b.resetsAt))
    if (loginDead(account.usage, account.active)) parts.push("log in again")
    return parts.length > 0 ? "(" + parts.join(", ") + ")" : ""
  }

  // right-hand figures: what is left of the session, of the week, and of
  // each model window, in that order; the hover text names them. A used-up
  // account just says so.
  function figuresText(usage) {
    if (usageState(usage, false) === "blocked") return "limit"
    var s = sessionLimit(usage), w = weeklyLimit(usage)
    var parts = []
    if (s) parts.push((100 - s.percent) + "%")
    if (w) parts.push((100 - w.percent) + "%")
    if (!usage) return parts.join(" · ")
    for (var i = 0; i < usage.limits.length; i += 1) {
      var l = usage.limits[i]
      if (l === s || l === w || l.percent < 0) continue
      parts.push((100 - l.percent) + "%")
    }
    return parts.join(" · ")
  }

  function accountTooltip(p, a) {
    var lines = [a.email + (a.plan !== "" ? " · " + a.plan : "") + (a.active ? " · current" : "")]
    if (!a.usage) lines.push("Usage not probed yet")
    else if (a.usage.limits.length === 0) lines.push(a.usage.note !== "" ? a.usage.note : "No limits reported")
    else for (var i = 0; i < a.usage.limits.length; i += 1) {
      var l = a.usage.limits[i]
      var when = l.resetsAt !== "" ? " · resets in " + resetLong(l.resetsAt) : ""
      var left = l.percent >= 100 ? "limit reached" : (100 - l.percent) + "% left"
      lines.push(l.label + ": " + left + when)
    }
    if (a.usage && a.usage.fetchedAt > 0) lines.push("Probed " + ageText(a.usage.fetchedAt))
    if (usageState(a.usage, a.active) === "dead") lines.push("Click to log in to this account again")
    else if (!a.active) lines.push("Click to switch " + p.title + " to this account")
    return lines.join("\n")
  }

  function ageText(at) {
    var min = Math.max(0, Math.round((nowMs / 1000 - at) / 60))
    return min < 1 ? "just now" : min + " min ago"
  }

  function usageAge() {
    var at = status.newestUsageAt()
    return at <= 0 ? "" : ageText(at)
  }

  // ---------------------------------------------------------------- cursor
  function actionKey(a) {
    return a.kind + "\n" + a.provider + "\n" + (a.kind === "use" ? a.email : "")
  }

  function actionIndexFor(kind, provider, email) {
    for (var i = 0; i < actions.length; i += 1) {
      var a = actions[i]
      if (a.kind === kind && a.provider === provider && (kind !== "use" || a.email === email)) return i
    }
    return -1
  }

  function actionItem(index) {
    var a = actions[index]
    if (!a) return null
    if (a.kind === "usage") return usageRow
    for (var i = 0; i < view.length; i += 1) {
      if (view[i].id !== a.provider) continue
      var block = providerRepeater.itemAt(i)
      if (!block) return null
      if (a.kind === "use") {
        for (var j = 0; j < view[i].accounts.length; j += 1)
          if (view[i].accounts[j].email === a.email) return block.accountRows.itemAt(j)
        return null
      }
      return a.kind === "save" ? block.saveRow : block.addRow
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
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maximum = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin)
        panelFlick.contentY = Math.min(maximum, bottom + margin - panelFlick.height)
    })
  }

  // hover only moves the highlight; keyboard movement also scrolls, so a
  // wheel scroll never has rows re-scrolling the view under a still pointer
  function pointCursor(index) {
    if (actions.length === 0) return
    cursorActive = true
    cursor = Math.max(0, Math.min(actions.length - 1, index))
    cursorKey = actionKey(actions[cursor])
  }

  function setCursor(index) {
    pointCursor(index)
    scrollIntoView(actionItem(cursor))
  }

  onActionsChanged: {
    if (!cursorActive || cursorKey === "") return
    for (var i = 0; i < actions.length; i += 1)
      if (actionKey(actions[i]) === cursorKey) { cursor = i; return }
    cursor = Math.max(0, Math.min(actions.length - 1, cursor))
    cursorKey = actions.length > 0 ? actionKey(actions[cursor]) : ""
  }

  function moveCursor(dx, dy) {
    if (!cursorActive) { setCursor(cursor); return }
    var delta = dy !== 0 ? dy : dx
    if (delta !== 0) setCursor(cursor + (delta > 0 ? 1 : -1))
  }

  // a dead saved login cannot be switched to; the row starts a fresh login
  function useOrReadd(provider, email) {
    for (var i = 0; i < providers.length; i += 1) {
      if (providers[i].id !== provider) continue
      for (var j = 0; j < providers[i].accounts.length; j += 1) {
        var a = providers[i].accounts[j]
        if (a.email !== email) continue
        if (usageState(a.usage, a.active) === "dead") { root.close(); status.add(provider, email); return }
      }
    }
    status.use(provider, email)
  }

  function activate() {
    if (status.busy || actions.length === 0) return
    var a = actions[Math.max(0, Math.min(actions.length - 1, cursor))]
    if (a.kind === "use") { if (!a.active) useOrReadd(a.provider, a.email) }
    else if (a.kind === "save") status.save(a.provider)
    else if (a.kind === "add") { root.close(); status.add(a.provider) }
    else if (a.kind === "usage") status.probeUsage()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onOpenedChanged: {
    status.panelOpen = opened
    if (!opened) { status.actionError = ""; return }
    cursorActive = false
    cursorKey = ""
    autoProbed = false
    panelFlick.contentY = 0
    nowMs = Date.now()
    status.refresh()
    maybeAutoProbe()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Status {
    id: status
    refreshIntervalSec: Number(root.setting("refreshIntervalSec", 120))
  }

  // Stale numbers cannot say which account to switch to, so every open asks
  // for fresh ones. Checked on open against the cached model and again when
  // the model arrives; once per open, so a probe that yields nothing starts
  // no other.
  function maybeAutoProbe() {
    if (autoProbed || !opened || status.busy || providers.length === 0) return
    var any = false
    for (var i = 0; i < providers.length; i += 1) if (providers[i].accounts.length > 0) any = true
    if (!any) return
    autoProbed = true
    status.probeUsage()
  }

  Connections {
    target: status
    function onProvidersChanged() { root.maybeAutoProbe() }
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
    text: "󰀙"
    foreground: root.stateColor
    tooltipText: root.tooltip()
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activate()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

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
          spacing: Style.space(10)

          PanelHero {
            width: parent.width
            title: "AI accounts"
            meta: status.busy ? "Working…" : (status.refreshing ? "Refreshing…"
              : (status.availability === "ready"
                ? (root.usageAge() !== "" ? "Usage probed " + root.usageAge() : "Saved logins")
                : "Unavailable"))
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

          Text {
            visible: status.error !== "" || status.message !== ""
            width: parent.width
            text: status.error !== "" ? status.error : status.message
            color: status.error !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
          }

          ActionRow {
            visible: root.failed && !status.refreshing
            label: "Retry"
            onActivated: status.refresh()
          }

          Repeater {
            id: providerRepeater
            model: root.view

            delegate: Column {
              id: providerBlock
              required property var modelData
              readonly property alias accountRows: accountRepeater
              readonly property alias saveRow: saveAction
              readonly property alias addRow: addAction
              width: content.width
              spacing: Style.space(4)

              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader {
                text: providerBlock.modelData.title.toUpperCase()
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                visible: providerBlock.modelData.error !== "" || !providerBlock.modelData.live
                width: parent.width
                leftPadding: Style.space(8)
                text: providerBlock.modelData.error !== "" ? providerBlock.modelData.error : "Not logged in"
                color: providerBlock.modelData.error !== "" ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
                maximumLineCount: 3
              }

              Repeater {
                id: accountRepeater
                model: providerBlock.modelData.accounts

                delegate: AccountRow {
                  required property var modelData
                  provider: providerBlock.modelData
                  account: modelData
                  actionIndex: root.actionIndexFor("use", providerBlock.modelData.id, modelData.email)
                }
              }

              ActionRow {
                id: saveAction
                visible: actionIndex >= 0
                actionIndex: root.actionIndexFor("save", providerBlock.modelData.id, "")
                label: "Save the current login"
                onActivated: status.save(providerBlock.modelData.id)
              }

              ActionRow {
                id: addAction
                actionIndex: root.actionIndexFor("add", providerBlock.modelData.id, "")
                label: "Add account…"
                onActivated: { root.close(); status.add(providerBlock.modelData.id) }
              }
            }
          }

          PanelSeparator { visible: root.providers.length > 0; foreground: root.foreground }

          ActionRow {
            id: usageRow
            visible: root.providers.length > 0
            actionIndex: root.actionIndexFor("usage", "", "")
            label: "Refresh usage"
            detail: root.usageAge()
            onActivated: status.probeUsage()
          }
        }
      }
    }
  }

  // A saved account: colored dot, email, plan (with the reset countdown while
  // blocked), and the session and weekly figures on the right. No box: the
  // row lights up under the pointer or the keyboard cursor, as the shell's
  // own lists do.
  component AccountRow: Item {
    id: row
    property var provider: null
    property var account: null
    property int actionIndex: -1
    readonly property string state: root.usageState(account ? account.usage : null, active)
    readonly property bool active: !!account && account.active
    readonly property bool highlighted: (root.cursorActive && root.cursor === actionIndex) || rowMouse.containsMouse
    readonly property bool enabled: !status.busy && !active

    width: parent.width
    implicitHeight: Math.max(emailText.implicitHeight, figures.implicitHeight) + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, row.highlighted ? 0.10 : (row.active ? 0.05 : 0))
    }

    Rectangle {
      id: dot
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(8)
      height: width
      radius: width / 2
      color: root.colorFor(row.state)
      opacity: row.state === "unknown" ? 0.6 : 1
    }

    Text {
      id: emailText
      anchors.left: dot.right
      anchors.leftMargin: Style.space(8)
      anchors.right: figures.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: row.account ? row.account.email + "  " : ""
      color: row.active ? Color.accent : (row.state === "blocked" || row.state === "dead" ? root.dim : root.foreground)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: row.active
      elide: Text.ElideMiddle

      Text {
        anchors.left: parent.left
        anchors.leftMargin: parent.contentWidth
        anchors.verticalCenter: parent.verticalCenter
        text: row.account ? root.planText(row.account) : ""
        color: row.state === "blocked" || row.state === "dead" ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        visible: parent.contentWidth + implicitWidth <= parent.width
      }
    }

    Text {
      id: figures
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: row.account ? root.figuresText(row.account.usage) : ""
      color: root.colorFor(row.state)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: row.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: if (containsMouse) root.pointCursor(row.actionIndex)
      onClicked: if (row.enabled) root.useOrReadd(row.provider.id, row.account.email)
    }

    PanelToolTip {
      visible: rowMouse.containsMouse && !!row.account
      text: row.account ? root.accountTooltip(row.provider, row.account) : ""
      fontFamily: root.fontFamily
    }
  }

  // A flat command line ("Add account…") with the same hover and cursor fill.
  component ActionRow: Item {
    id: action
    property string label: ""
    property string detail: ""
    property int actionIndex: -1
    signal activated()
    readonly property bool highlighted: (root.cursorActive && root.cursor === actionIndex) || actionMouse.containsMouse

    width: parent.width
    implicitHeight: actionLabel.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, action.highlighted ? 0.10 : 0)
    }

    Text {
      id: actionLabel
      anchors.left: parent.left
      anchors.leftMargin: Style.space(26)
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
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: status.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse && action.actionIndex >= 0) root.pointCursor(action.actionIndex)
      onClicked: if (!status.busy) action.activated()
    }
  }
}
