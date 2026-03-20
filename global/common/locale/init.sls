Europe/Paris:
  timezone.system

locales_pkg:
  pkg.installed:
    - name: locales

en_US.UTF-8 UTF-8:
  locale.present

/etc/default/locale:
  file.managed:
    - source: salt://global/common/locale/files/default-locale
    - user: root
    - group: root
    - mode: 644

/etc/default/keyboard:
  file.managed:
    - source: salt://global/common/locale/files/default-keyboard
    - user: root
    - group: root
    - mode: 644
    - require:
      - pkg: keyboard_configuration_pkg

console_setup_pkg:
  pkg.installed:
    - name: console-setup

keyboard_configuration_pkg:
  pkg.installed:
    - name: keyboard-configuration
