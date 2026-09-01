# Omarchy Lid

Keep working with the lid closed — one tap left of the clock.

![Lid icon](https://img.shields.io/badge/Omarchy-bar--widget-9cf)

> **Exactamente donde tu captura:** en la franja de indicadores de la barra (`omarchy.indicators`), a la izquierda del reloj. Es esa fila de 6 iconos (🎙️ ● ⚓ … ☕). Tras instalar, Lid aparece como **7º icono** justo entre el grupo de indicadores y el reloj (`omarchy.clock`). Dim cuando está off (0.45), brillo completo cuando está on — igual que los otros 6.

## Qué hace

- **Lid off (stock):** cerrar tapa → `suspend-then-hibernate` (+ lock si no hay monitor externo). Es lo que tienes en `/etc/systemd/logind.conf.d/99-lid.conf:1` + `omarchy-system-lid-close:13`.
- **Lid on (este plugin):** cerrar tapa → solo apaga el panel (`eDP-1` via `omarchy-hyprland-monitor-clamshell`), **sin suspender, sin hibernar, sin bloquear** por defecto. La máquina sigue trabajando. Con dock (externo) ya era clamshell — sin regresión.

Opcional: activar **Lock on lid** para que, aun con Lid Ignore on, sí bloquee al cerrar.

## Instalación

```bash
git clone https://github.com/tymurbogach/omarchy-lid.git
cd omarchy-lid
./install.sh
# habilita y coloca el icono justo izq. del reloj (entre indicadores y reloj)
# si ya tenías el repo, solo: ./install.sh --sync
```

También vía plugin manager:
```bash
omarchy plugin add https://github.com/tymurbogach/omarchy-lid.git --enable
omarchy plugin enable io.github.tymurbogach.lid --before omarchy.clock
```

Valida con:
```bash
omarchy-plugin-validate .
omarchy-lid status --json
systemd-inhibit --list | grep -i lid   # debe mostrar "Omarchy Lid  handle-lid-switch  block"
```

## Uso

- **Barra:** icono `󰋊` (cerrada) / `󰍹` (abierta) justo a la izq. del reloj. Click → panel con dos switches:
  - **Lid Ignore** — tapa cerrada sigue trabajando, pantalla off
  - **Lock on lid** — bloquear al cerrar (opt-in, off por defecto = tu “ni se cierre sesión ni nada”)
  - **Repair / Uninstall**
- **Terminal:**
```bash
omarchy-lid status              # humano
omarchy-lid status --json       # {"active":true,"inhibitActive":true,"lockOnLid":false}
omarchy-lid lid on|off|toggle
omarchy-lid lock on|off|toggle
omarchy-lid doctor              # reconcilia toggle vs servicio systemd
omarchy-lid lid on && systemd-inhibit --list | grep -i lid
```

Mover el icono:
```bash
omarchy bar put io.github.tymurbogach.lid --before omarchy.clock   # izq del reloj (default)
omarchy bar put io.github.tymurbogach.lid --after omarchy.indicators
omarchy bar move io.github.tymurbogach.lid --section center --index 1
```

## Cómo funciona (sin sudo)

- **Inhibidor:** `systemd-inhibit --what=handle-lid-switch --who="Omarchy Lid" sleep infinity` en un user service `omarchy-lid-inhibit.service` (`~/.config/systemd/user/`). `lid on` → `systemctl --user enable --now`, `lid off` → `disable --now`. Sobrevive a `omarchy-restart-shell`; no escribe fuera de `$HOME`, así pasa `omarchy-plugin-validate`.
- **Sin lock:** Hyprland dispara `omarchy-system-lid-close` en `switch:on:Lid Switch` (`default/hypr/bindings/utilities.lua:34`). El plugin instala un shim en `~/.local/bin/omarchy-system-lid-close` (prioritario en `$PATH`) que, cuando `lid-ignore` + `!lid-lock`, solo ejecuta `omarchy-hyprland-monitor-clamshell` (apaga `eDP-1`), saltándose `omarchy-system-lock`.
- **Persistencia:** `~/.local/state/omarchy/toggles/lid-ignore` y `lid-lock` (patrón `omarchy-toggle:10`, `StayAwake.qml:6`). `doctor` reconcilia estado toggles vs inhibitor.

## Verificación

```bash
omarchy-lid lid on
systemd-inhibit --list | grep Lid   # block
# cerrar tapa 10s sin dock:
hyprctl monitors                    # eDP-1 disabled
journalctl -u systemd-logind --since "1 min ago" | grep -i suspend  # nada
omarchy-lid lid off                 # vuelve a stock
```

Al abrir tapa, `omarchy-hyprland-monitor-clamshell` reactiva `eDP-1`.

## Publicación en plugins.omarchy.org

- `manifest.json` en raíz, `id` reverse-DNS no reservado (`io.github.tymurbogach.lid`), `schemaVersion:1`, `kinds:["bar-widget"]`, `entryPoints.barWidget:"Panel.qml"`.
- Repo git público + tag `v0.1.0` + este README con `omarchy plugin add <url> --enable`.

## Uninstall

```bash
./uninstall.sh
# o
omarchy-lid-uninstall
# deja toggles y servicio borrados; tapa vuelve a suspender (off = gone)
```

## Licencia

MIT
