import QtQuick
import qs.Commons as Commons
import qs.Ui

BarIndicator {
  id: root

  readonly property var sleepService: bar?.shell?.serviceFor("io.github.tymurbogach.sleepwalker")

  active: sleepService ? sleepService.remoteSession : false
  activeText: "󰢹"
  activeTooltipText: Commons.I18n.t("bar.remoteSession")
  useActiveColor: true
  activeColor: Commons.Color.urgent
  revealWhenInactive: false

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() {
      if (root.sleepService) root.sleepService.refreshIndicatorStates()
    }
  }
}
