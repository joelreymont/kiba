import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

// Bar widget: shows the live account per provider and switches through the switcher CLI.
Panel {
  id: root
  moduleName: "joel.switcher"
  ipcTarget: "joel.switcher"

  property bool cursorActive: false
  property int cursor: 0
  property string cursorKey: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var providers: status.providers
  readonly property bool alerting: status.error !== ""
  readonly property bool inactive: status.availability !== "ready"
  readonly property bool failed: status.availability === "failed" || status.availability === "malformed"
    || status.availability === "missing"
  readonly property color stateColor: alerting ? urgent : (inactive ? dim : foreground)

  // One flat cursor over every row that can be activated, in panel order.
  readonly property var actions: {
    var out = []
    for (var i = 0; i < providers.length; i += 1) {
      var p = providers[i]
      for (var j = 0; j < p.accounts.length; j += 1)
        out.push({ kind: "use", provider: p.id, email: p.accounts[j].email, active: p.accounts[j].active })
      if (p.live && p.error === "" && !liveSaved(p)) out.push({ kind: "save", provider: p.id })
      out.push({ kind: "add", provider: p.id })
    }
    return out
  }

  function liveSaved(p) {
    for (var j = 0; j < p.accounts.length; j += 1)
      if (p.accounts[j].email === p.live.email) return true
    return false
  }

  function shortEmail(email) {
    var at = String(email || "").indexOf("@")
    return at > 0 ? String(email).substring(0, at) : String(email || "")
  }

  function liveText(p) {
    if (p.error !== "") return p.error
    if (!p.live) return "not logged in"
    return p.live.email + (p.live.plan !== "" ? " · " + p.live.plan : "")
  }

  function tooltip() {
    if (status.availability !== "ready") return "AI accounts"
    var parts = []
    for (var i = 0; i < providers.length; i += 1)
      parts.push(providers[i].title + ": " + (providers[i].live ? providers[i].live.email : "none"))
    return parts.join("\n")
  }

  function actionIndexFor(kind, provider, email) {
    for (var i = 0; i < actions.length; i += 1) {
      var a = actions[i]
      if (a.kind === kind && a.provider === provider && (kind !== "use" || a.email === email)) return i
    }
    return -1
  }

  function actionKey(a) {
    return a.kind + "\n" + a.provider + "\n" + (a.kind === "use" ? a.email : "")
  }

  function actionItem(index) {
    var a = actions[index]
    if (!a) return null
    for (var i = 0; i < providers.length; i += 1) {
      if (providers[i].id !== a.provider) continue
      var block = providerRepeater.itemAt(i)
      if (!block) return null
      if (a.kind === "use") {
        for (var j = 0; j < providers[i].accounts.length; j += 1)
          if (providers[i].accounts[j].email === a.email) return block.accountRows.itemAt(j)
        return null
      }
      return a.kind === "save" ? block.saveButton : block.addButton
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

  function setCursor(index) {
    if (actions.length === 0) return
    cursorActive = true
    cursor = Math.max(0, Math.min(actions.length - 1, index))
    cursorKey = actionKey(actions[cursor])
    scrollIntoView(actionItem(cursor))
  }

  // The list changes after save/use/forget: follow the same action if it survived.
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

  function activate() {
    if (status.busy || actions.length === 0) return
    var a = actions[Math.max(0, Math.min(actions.length - 1, cursor))]
    if (a.kind === "use") { if (!a.active) status.use(a.provider, a.email) }
    else if (a.kind === "save") status.save(a.provider)
    else if (a.kind === "add") { root.close(); status.add(a.provider) }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onOpenedChanged: {
    if (!opened) { status.actionError = ""; return }
    cursorActive = false
    cursorKey = ""
    panelFlick.contentY = 0
    status.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Status {
    id: status
    refreshIntervalSec: Number(root.setting("refreshIntervalSec", 120))
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
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(560))

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
              : (status.availability === "ready" ? "Saved logins" : "Unavailable"))
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

          Button {
            visible: root.failed && !status.refreshing
            width: parent.width
            text: "Retry"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: status.refresh()
          }

          Repeater {
            id: providerRepeater
            model: root.providers

            delegate: Column {
              id: providerBlock
              required property var modelData
              readonly property alias accountRows: accountRepeater
              readonly property alias saveButton: saveRow
              readonly property alias addButton: addRow
              width: content.width
              spacing: Style.space(6)

              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader {
                text: providerBlock.modelData.title.toUpperCase()
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              Text {
                width: parent.width
                text: root.liveText(providerBlock.modelData)
                color: providerBlock.modelData.error !== "" ? root.urgent
                  : (providerBlock.modelData.live ? root.foreground : root.dim)
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideMiddle
              }

              Repeater {
                id: accountRepeater
                model: providerBlock.modelData.accounts

                delegate: Button {
                  required property var modelData
                  readonly property int actionIndex: root.actionIndexFor("use", providerBlock.modelData.id, modelData.email)
                  width: providerBlock.width
                  text: (modelData.active ? "● " : "○ ") + modelData.email
                    + (modelData.plan !== "" ? "  (" + modelData.plan + ")" : "")
                  foreground: modelData.active ? Color.accent : root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  enabled: !status.busy && !modelData.active
                  hasCursor: root.cursorActive && root.cursor === actionIndex
                  onHovered: function(isHovered) { if (isHovered) root.setCursor(actionIndex) }
                  onClicked: status.use(providerBlock.modelData.id, modelData.email)
                }
              }

              Row {
                id: providerButtons
                width: parent.width
                spacing: Style.space(6)

                Button {
                  id: saveRow
                  readonly property int actionIndex: root.actionIndexFor("save", providerBlock.modelData.id, "")
                  visible: actionIndex >= 0
                  width: (providerButtons.width - providerButtons.spacing) / 2
                  text: "Save current"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  enabled: !status.busy
                  hasCursor: root.cursorActive && root.cursor === actionIndex
                  onHovered: function(isHovered) { if (isHovered) root.setCursor(actionIndex) }
                  onClicked: status.save(providerBlock.modelData.id)
                }
                Button {
                  id: addRow
                  readonly property int actionIndex: root.actionIndexFor("add", providerBlock.modelData.id, "")
                  width: (providerButtons.width - providerButtons.spacing) / 2
                  text: "Add account…"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: !status.busy
                  hasCursor: root.cursorActive && root.cursor === actionIndex
                  onHovered: function(isHovered) { if (isHovered) root.setCursor(actionIndex) }
                  onClicked: { root.close(); status.add(providerBlock.modelData.id) }
                }
              }
            }
          }
        }
      }
    }
  }
}
