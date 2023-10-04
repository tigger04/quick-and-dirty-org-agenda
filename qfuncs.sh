#shellcheck disable=SC2119
#    this to avoid silly warnings as shellcheck can't handle pointers which
#    are fantastic for bash optimization 🥳

# WTF is this thing:
#    Handy functions, trying to avoid subshells at all costs which slow down
#    execution (these things all add up til one day 😐🔫 trust me)

# Why no ANSI colours? I abandoned these in favour of emojis which still stand
# out. Too much faff when capturing output to log files etc

# KEY:
#    for USAGE comments, OPTION is mandatory argument, [OPTION] is optional
#    argument
# e.g.
#    USAGE: some_function [SOME_OPTIONAL_ARGUMENT] SOME_MANDATORY_ARGUMENT

### quick and dirty path fix ###
PATH=~/bin:~/wonky:~/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:"$PATH"

### fatal function ###
die() {
   # USAGE:
   #    SOME_RISKY_COMMAND || die [MESSAGE]
   # WTF:
   #    Halts execution if SOME_RISKY_COMMAND fails, allowing some useful
   #    explanation to be displayed to the user

   rc=$?
   printf "💀 %s died with exit code %s: %s\n" "$cmd_base" $rc "$*" >/dev/stderr
   exit $rc
}

### bash version check ###
declare -p BASH_VERSINFO
[ ${BASH_VERSINFO[0]} -lt 5 ] &&
   die "bash version found: $BASH_VERSION, requires bash 5+"

# What OS are we on? (Linux or Darwin mainly)
_os=${OSTYPE%%[0-9-]*}
_os=${_os^}
[ -z "$_os" ] && _os="$(uname)"
declare -x _os

### functions ###

qbase() {
   # get basename of a file without unnecessary subshell
   # usage: qbase PATH [VAR]
   # result is in $REPLY or $VAR if specified
   # adapted from the pure bash bible :) no need for additional time-consuming subshells :)

   [ $# -ge 1 ] || return 1 # min 1 and max 1 argument please

   REPLY=${1%"${1##*[!/]}"}
   REPLY=${REPLY##*/}
   REPLY=${REPLY%"${2/"$REPLY"/}"}

   if [ -n "$2" ]; then
      local -n ptr=${2}
      ptr="$REPLY"
   fi

   # printf -v REPLY '%s' "${tmp}"
}

hline() {

   # pretty print a header/title or else just a spacer line
   # USAGE: hline [TITLE]

   local cols tmp_out
   ((cols = COLUMNS > 0 ? COLUMNS - 1 : 65))

   local hline_bullet='='

   # simplifying this to use local vars - was too complex and unpredictable letting these be set externally
   if [ -n "$thinbanner_pointer_open" ] ||
      [ -n "$thinbanner_pointer_close" ] ||
      [ -n "$thinbanner_bullet" ] ||
      [ -n "$thinbanner_bullet_r" ]; then
      warn "pre-setting of thinbanner variables no longer supported"
      verbose_var -v FUNCNAME BASH_SOURCE
   fi

   local thinbanner_bullet="-"
   local thinbanner_pointer_open="> "
   local thinbanner_pointer_close=" <"

   if [ $# -eq 0 ]; then
      printf -v tmp_out "%${cols}s"
      printf '%s' "${tmp_out// /$hline_bullet}"
   else

      local displaytext="$*"
      local displayoutput=""

      local displaytext_length=${#displaytext}
      local pointer_open_length=${#thinbanner_pointer_open}
      local pointer_close_length=${#thinbanner_pointer_close}
      local bullet_length=${#thinbanner_bullet}

      local bullets

      bullets=$((((cols - displaytext_length) / 2 - pointer_open_length - pointer_close_length) / bullet_length))

      printf -v tmp_out "%${bullets}s"                  # sets to n amount of spaces
      displayoutput+="${tmp_out// /$thinbanner_bullet}" # replace spaces with bullets

      displayoutput+="$thinbanner_pointer_open"
      displayoutput+="$displaytext"
      displayoutput+="$thinbanner_pointer_close"

      local r_bullets_length=$((${#displayoutput} - cols))
      printf -v tmp_out "%${r_bullets_length}s" # set n number of spaces
      displayoutput+="${tmp_out// /$thinbanner_bullet}"

      printf '%s' "$displayoutput"
   fi

   echo
}

thinbanner() {
   # wrapper for hline
   hline "$@"
}

qhead() {
   # basically this is 'head' without resorting to external binary and subshell
   # Usage: qhead NUM_LINES FILE
   mapfile -tn "$1" line <"$2"
   printf '%s\n' "${line[@]}"

   #TODO: support STDIN
}

qtail() {
   # basically this is 'tail' without resorting to external binary and subshell
   # Usage: qtail NUM_LINES FILE
   mapfile -tn 0 line <"$2"
   printf '%s\n' "${line[@]: -$1}"

   #TODO: support STDIN
}

uuid() {
   # WTF: quickly generate a UUID (aka GUID)
   # Usage: uuid [VAR]
   # result in VAR or REPLY

   local abit b c theuuid
   local theuuid=""

   c="89ab"

   for ((n = 0; n < 16; ++n)); do
      b="$((RANDOM % 256))"

      case "$n" in
      6)
         printf -v abit '4%x' "$((b % 16))"
         ;;
      8)
         printf -v abit '%c%x' "${c:$RANDOM%${#c}:1}" "$((b % 16))"
         ;;

      3 | 5 | 7 | 9)
         printf -v abit '%02x-' "$b"
         ;;

      *)
         printf -v abit '%02x' "$b"
         ;;
      esac

      theuuid+="$abit"
   done

   if [ $# -eq 0 ]; then
      REPLY="$theuuid"
   else
      local -n ptr=${1}
      ptr="$theuuid"
   fi
}

trim_quotes() {

   # Usage: trim_quotes VAR_1 VAR_2 .. VAR_n
   # result(s) in VAR_1, VAR_2 .. VAR_n

   while [ $# -gt 0 ]; do
      local -n ptr=${1}
      ptr="${ptr//\"/}"
      shift
   done
}

quote_quotes() {

   # Usage: quote_quotes VAR_1 VAR_2 .. VAR_n
   # result(s) in VAR_1, VAR_2 .. VAR_n

   while [ $# -gt 0 ]; do
      local -n ptr=${1}
      ptr="${ptr//\"/\\\"}"
      shift
   done
}

ok_confirm() {

   # WTF:   Pause execution pending user confirmation y/N

   # USAGE: ok_confirm [OPTIONAL_TIMEOUT_SECONDS] [OPTIONAL_MESSAGE]
   #        caller must handle response code or execution will proceed
   #        (unless 'set -e' set in script in which case it will abort)

   local ok_timeout=15 # default

   [[ $1 =~ ^([0-9]+)$ ]] && ok_timeout=${BASH_REMATCH[1]} && shift

   if [ $# -eq 0 ]; then
      echo -ne "Continue (y/N)?"
   else
      echo -ne "$* (y/N)?"
   fi

   while [ $ok_timeout -gt 0 ]; do
      read -r -n 1 -t 1 ok_conf_reply || ok_conf_reply="!"
      echo -n '.'
      ((ok_timeout--)) || :

      if [[ ${ok_conf_reply,,} == y ]]; then
         echo
         return 0
      elif [[ "${ok_conf_reply}" != "!" ]]; then
         echo
         warn Cancelled
         return 1
      fi

   done

   errortext timed out
   return 1
}

warn() {
   # USAGE: warn MESSAGE
   echo -e "⚠️ $*" >/dev/stderr
}

errortext() {
   # USAGE: errortext MESSAGE
   # this does not halt execution, just displays an error!
   echo -e "⛔️ $*" >/dev/stderr
}

filename() {
   # display filename with icon (no newline!)

   printf "%s" "🗎 "

   if [[ "$1" == "$HOME/"* ]]; then
      printf "%s" "~${1#"$HOME"}"
   else
      printf "%s" "$1"
   fi
}

announce() {
   # USAGE: errortext MESSAGE
   {
      echo -e "📣 $*"
   } >/dev/stderr
}

info() {
   echo -e "🔹 $*" >&2
}

highlight() {
   {
      echo -e "*️⃣ $*"
   } >&2
}

confirm_cmd_execute() {

   # WTF: show command to user and request explicit y/N to execute it
   #      calling script must handle response code or execution will proceed,
   #      unless `set -e` is set in the calling script.

   # USAGE: confirm_cmd_execute [TIMEOUT_SECONDS] COMMAND

   local timeout=(-t 15) # default timeout 15s

   if [[ $1 =~ ^-([0-9]+).*$ ]]; then

      local t="${BASH_REMATCH[1]}"

      if [ $t -eq 0 ]; then
         timeout=()
         # ^ no timeout
      else
         timeout=(-t "$t")
      fi
      shift
   fi

   {
      echo -ne "$*"
      echo '? (y/N):'
   } >/dev/stderr

   read -r -n 1 "${timeout[@]}" || return 2
   echo

   # declare -p timeout REPLY
   # return

   if [[ ${REPLY,,} == y ]]; then
      "$@"
      return $?
   else
      warn "cancelled $*"
      return 1
   fi
}

show_cmd_execute() {
   printf '%s %s' "⚡" "$*" >/dev/stderr
   "$@"
}

fullpath() {
   # try and get the full path without using executable or subshell
   # usage: fullpath PATH [VAR]
   # result in $REPLY and VAR if specified

   local path="$1"
   if [ -n "$2" ]; then
      local -n ptr=${2}
   fi

   local parent=""
   local full_path=""

   if [[ "$path" == /* ]]; then
      full_path="$path"
   else
      parent="${PWD}"
      if [[ "${parent}" != */ ]]; then
         parent="${parent}/"
      fi
      full_path="${parent}${path}"
   fi

   # remove dots from ~/something/./something
   full_path="${full_path//\/.\//\/}"

   ptr="$full_path"
   REPLY="$ptr"
}

q_path() {
   deprecated 5
   fullpath "$@"
}

nicepath() {
   # usage: nicepath PATH [VAR]
   # result in $REPLY and VAR if specified
   local ugly_path="$1"
   if [ -n "$2" ]; then
      local -n ptr=${2}
   fi

   if [[ "$ugly_path" == "$HOME"* ]] || [[ "$ugly_path" == "$HOME" ]]; then
      printf -v nice_path '%s' "~${ugly_path#"$HOME"}"
   else
      printf -v nice_path '%s' "$ugly_path"
   fi

   ptr="$nice_path"
   REPLY="$ptr"
}

deprecated() {

   case $1 in
   1)
      warn "${FUNCNAME[1]} deprecated"
      declare -p FUNCNAME BASH_SOURCE
      return 0
      ;;
   5)
      warn "${FUNCNAME[1]} is flagged for future deprecation"
      return 0
      ;;
   *)
      warn "${FUNCNAME[1]} deprecated permanently: $*"

      if [ $SHLVL -le 1 ]; then
         pause this shell will quit
      fi
      exit 101 # calling 'die' seems to cause an infinite loop on maybe_rm
      ;;
   esac
}

timestamp() {
   # usage: timestamp [VAR]
   # assign timestamp to VAR if specified, otherwise echo it to STDOUT
   # timestamp assigned to REPLY in either case

   printf -v REPLY '🕘 %(%F %H:%M:%S)T' -1

   if [ $# -eq 0 ]; then
      echo "$REPLY"
   else
      local -n ptr=${1}
      ptr="$REPLY"
   fi
}

grep() {
   if [[ "$_os" == "Darwin" ]]; then
      command -v ggrep >/dev/null 2>&1 || die "GNU Grep required (brew install grep)"
      ggrep "$@"
   else
      grep "$@"
   fi
}

### aliases to functions ###
alias qbasename=qbase
# alias qbase=qbasename

### quick variables ###

# are quick functions loaded? this so scripts can check quickly
export qf_loaded=true

# basename of the running script for scripts to be able to use quickly
qbase "$0" cmd_base
export cmd_base
