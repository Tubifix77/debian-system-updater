#!/bin/bash
# Integration tests for update_system.sh.
#
# The tests run the real script as root, write /etc/default/debian-system-updater,
# install packages and add an unreachable apt source for a moment. They therefore
# refuse to run anywhere but a throwaway Debian container or VM with UPDATER_TESTS=1
# (the CI workflow sets it). Locally, for example:
#   docker run --rm -v "$PWD:/src" -w /src -e UPDATER_TESTS=1 debian:trixie bash tests/run_tests.sh
set -u

if [ "${UPDATER_TESTS:-}" != 1 ] || [ "$EUID" -ne 0 ]; then
    echo "Refusing to run: these tests need root and UPDATER_TESTS=1 (throwaway container or VM only)." >&2
    exit 2
fi

cd "$(dirname "$0")/.." || exit 2
SCRIPT="$PWD/update_system.sh"
CONF=/etc/default/debian-system-updater
UNREACHABLE=/etc/apt/sources.list.d/zz-updater-test-unreachable.list
# shellcheck source=/dev/null
. /etc/os-release
case "$VERSION_ID" in
    12) EXP_LTS=2028-06-30 ;;
    13) EXP_LTS=2030-06-30 ;;
    *)  echo "No expected dates for Debian ${VERSION_ID:-?}; add them to tests/run_tests.sh." >&2; exit 2 ;;
esac
export DEBIAN_FRONTEND=noninteractive

PASSES=0; FAILS=0
OUT=""; RC=0; RUN_NAME=""

# check DESCRIPTION COMMAND... : passes when the command succeeds
check() {
    local desc=$1; shift
    if "$@"; then
        echo "PASS  $desc"; PASSES=$((PASSES + 1))
    else
        echo "FAIL  $desc"; FAILS=$((FAILS + 1))
        tail -n 40 "/tmp/updater-test-$RUN_NAME.log" 2>/dev/null | sed 's/^/      | /'
    fi
}
has()           { grep -qF -- "$1" <<< "$OUT"; }     # output contains a fixed string
matches()       { grep -qE -- "$1" <<< "$OUT"; }     # output matches an extended regex
exit_is()       { [ "$RC" -eq "$1" ]; }
installed()     { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }
not_in_file()   { ! grep -q -- "$1" "$2"; }
not_installed() { ! installed "$1"; }
settings()      { printf '%s\n' "$@" > "$CONF"; }    # settings file for the next run

# updater NAME [VAR=value ...] [-- script arguments] : runs the script, sets OUT and RC
updater() {
    RUN_NAME=$1; shift
    local vars=()
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do vars+=("$1"); shift; done
    [ $# -gt 0 ] && shift
    env "${vars[@]}" bash "$SCRIPT" "$@" > "/tmp/updater-test-$RUN_NAME.log" 2>&1 < /dev/null
    RC=$?
    OUT=$(sed 's/\x1b\[[0-9;]*m//g' "/tmp/updater-test-$RUN_NAME.log")
    echo "--- run '$RUN_NAME': exit code $RC"
}

echo "== Testing update_system.sh on $PRETTY_NAME"

# Options and the root check (no system changes)
updater help LANG=C.UTF-8 -- --help
check "--help exits 0"                               exit_is 0
check "--help is English with LANG=C.UTF-8"          has "Usage:"
updater help-da LANG=da_DK.UTF-8 -- --help
check "--help is Danish with LANG=da_DK.UTF-8"       has "Brug:"
updater bad-option -- --bogus
check "an unknown option exits 2"                    exit_is 2
updater bad-lang -- --lang=xx
check "a bad --lang value exits 2"                   exit_is 2
RUN_NAME=nonroot
install -m 0755 "$SCRIPT" /tmp/update_system_nonroot.sh
su -s /bin/bash nobody -c 'bash /tmp/update_system_nonroot.sh' > /tmp/updater-test-nonroot.log 2>&1 < /dev/null
RC=$?
check "a run without root exits 1"                   exit_is 1

# The settings screen needs a terminal: script(1) provides one and types the keys
rm -f "$CONF"
RUN_NAME=settings
printf '2g' | script -qec "bash $SCRIPT --settings --lang=en" /dev/null > /tmp/updater-test-settings.log 2>&1
RC=$?
check "--settings in a terminal exits 0"             exit_is 0
check "--settings: keys 2 and G saved 'install'"     grep -qx 'FIRMWARE_UPDATES=install' "$CONF"
updater settings-no-tty -- --settings
check "--settings without a terminal exits 2"        exit_is 2
rm -f "$CONF"

# Run A: English, fallback date table, both switches off
settings 'INSTALL_SECURITY_SUPPORT=no' 'FIRMWARE_UPDATES=off' 'DISTRO_INFO_CSV=/nonexistent'
updater a LANG=C.UTF-8 -- --auto
check "A: exits 0"                                   exit_is 0
check "A: header shows $PRETTY_NAME"                 has "$PRETTY_NAME"
check "A: English report"                            has "REPORT"
check "A: apt counts are reported"                   matches 'Packages upgraded: +[0-9]+'
check "A: no errors"                                 matches 'Errors: +None'
check "A: support clock ends $EXP_LTS"               has "$EXP_LTS"
check "A: dates come from the built-in table"        has "Dates from: the script's built-in table"
check "A: firmware step switched off"                matches 'Firmware: +switched off'
check "A: debian-security-support not installed"     not_installed debian-security-support
check "A: the report explains why"                   matches 'Security support: +not installed'

# Run B: Danish, dates from a distro-info file, default switches
printf 'version,codename,series,created,release,eol,eol-lts,eol-elts\n%s,Test,%s,2020-01-01,2021-01-01,2029-01-01,2031-01-31,\n' \
    "$VERSION_ID" "$VERSION_CODENAME" > /tmp/test-distro-info.csv
settings 'DISTRO_INFO_CSV=/tmp/test-distro-info.csv'
updater b LANG=da_DK.UTF-8 -- --auto
check "B: exits 0"                                   exit_is 0
check "B: Danish report"                             has "RAPPORT"
check "B: no errors"                                 matches 'Fejl: +Ingen'
check "B: dates read from the distro-info file"      has "2031-01-31"
check "B: both support phases shown"                 has "fuld sikkerhedssupport til 2029-01-01"
check "B: date source named"                         has "Datoer fra: distro-info-data (/tmp/test-distro-info.csv)"
check "B: debian-security-support installed"         installed debian-security-support
check "B: security status reported"                  matches 'Sikkerhedssupport: +(ingen|alle|[0-9])'

# Run C: Debian's real distro-info-data, UI_LANG from the settings file, warning branch
apt-get install -y distro-info-data > /tmp/updater-test-install.log 2>&1
settings 'UI_LANG=en' 'LTS_WARN_DAYS=100000' 'LTS_END_NOTE=TEST-NOTE-123'
updater c LANG=da_DK.UTF-8 -- --auto
check "C: exits 0"                                   exit_is 0
check "C: UI_LANG=en in the settings file wins"      has "REPORT"
check "C: dates come from distro-info-data"          has "Dates from: distro-info-data (/usr/share/distro-info/debian.csv)"
check "C: distro-info-data gives $EXP_LTS"           has "$EXP_LTS"
check "C: yellow warning branch"                     has "security support ends in"
check "C: personal note shown"                       has "TEST-NOTE-123"

# Run D: --lang wins over the settings file; the "support ended" branch
settings 'UI_LANG=da' 'REGULAR_END=2019-01-01' 'LTS_END=2020-01-01'
updater d LANG=C.UTF-8 -- --auto --lang=en
check "D: exits 0"                                   exit_is 0
check "D: --lang=en wins over UI_LANG=da"            has "REPORT"
check "D: support-ended branch"                      has "SECURITY SUPPORT ENDED 2020-01-01"
check "D: dates come from the settings file"         has "Dates from: the settings file"

# Run E: an unreachable package source
rm -f "$CONF"
echo "deb http://127.0.0.1:9/debian $VERSION_CODENAME main" > "$UNREACHABLE"
updater e LANG=C.UTF-8 -- --auto
rm -f "$UNREACHABLE"
check "E: exits 1"                                   exit_is 1
check "E: the report shows the failed source"        matches 'Package sources: +ERROR'
check "E: the upgrade still ran"                     matches 'Packages upgraded: +[0-9]+'
check "E: exactly one error counted"                 matches 'Errors: +1 '

# Run F: an interactive run in a terminal; TAB at the end opens the settings
# screen, 3 switches the security-support check back to its default, G saves
# and ENTER exits
settings 'FIRMWARE_UPDATES=off' 'INSTALL_SECURITY_SUPPORT=no'
RUN_NAME=f
printf '\t3g\n' | script -qec "bash $SCRIPT --lang=en" /dev/null > /tmp/updater-test-f.log 2>&1
RC=$?
OUT=$(sed 's/\x1b\[[0-9;]*m//g' /tmp/updater-test-f.log)
check "F: interactive run exits 0"                   exit_is 0
check "F: the end prompt offers the settings screen" has "Press ENTER to exit or TAB for settings"
check "F: the change was saved (default, so no line)" not_in_file '^INSTALL_SECURITY_SUPPORT=' "$CONF"
check "F: the other setting was kept"                grep -qx 'FIRMWARE_UPDATES=off' "$CONF"
check "F: the settings screen stayed out of the log" not_in_file 'Keys 1-6' /var/log/debian-updater.log
rm -f "$CONF"

echo "== $PASSES passed, $FAILS failed"
[ "$FAILS" -eq 0 ]
