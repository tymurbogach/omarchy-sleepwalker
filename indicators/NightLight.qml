import QtQuick
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  readonly property var sleepService: bar?.shell?.serviceFor("io.github.tymurbogach.sleepwalker")

  active: sleepService ? sleepService.nightlightOn : false
  activeText: "󰔎"
  inactiveText: "󰔎"
  activeTooltipText: I18n.t("bar.dayLight")
  inactiveTooltipText: I18n.t("bar.nightLight")

  function toggle() {
    if (root.sleepService) root.sleepService.toggleIndicator("nightlight")
  }

  onPressed: function() { root.toggle() }
}
