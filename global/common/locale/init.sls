Europe/Paris:
  timezone.system

locales:
  pkg.installed

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
      - pkg: keyboard-configuration

console-setup:
  pkg.installed

keyboard-configuration:
  pkg.installed
