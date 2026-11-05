import QtQuick
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  readonly property var sleepService: bar?.shell?.serviceFor("io.github.tymurbogach.sleepwalker")

  active: sleepService ? sleepService.stayAwake : false
  // A mug without a saucer, which drew a line under the cup.
  activeText: ""
  inactiveText: ""
  activeTooltipText: I18n.t("bar.allowIdleLock")
  inactiveTooltipText: I18n.t("bar.stayAwake")

  function toggle() {
    if (root.sleepService) root.sleepService.toggleIndicator("idle")
  }

  onPressed: function() { root.toggle() }
}
