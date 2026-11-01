# --- vendored from cli-utilities/term.sh, cksum 3276722527 65019; do not edit ---
#
# term.sh -- the shared output renderer.  Sourced, never executed.
#
# The rules it implements are written down in conventions/docs/output.md.  If
# the two ever disagree, that is a bug in one of them, and the staleness test
# in each consuming repo is what says so.
#
# Three constraints shaped this file, and all three come from the consumers:
#
#   POSIX sh.  setup/dotfiles runs as #!/bin/sh under set -u, and its test suite
#   requires sh and zsh to produce identical bytes.  So: no arrays, no +=, no
#   $((n++)), no ${var:off:len}, no local.  The engine itself avoids local and
#   uses prefixed globals for the same reason, and this file follows it.
#
#   Prefixed names.  setup/dotfiles already has note, report, say, warn, die and
#   step.  A library that defined any of those would break the engine in a way
#   that only shows up on somebody's machine.  Every name here starts term_.
#
#   Colour is a property of the terminal, not of the text.  Nothing is coloured
#   when stdout is not a terminal, when TERM is dumb, or when NO_COLOR is set,
#   so piped output and the test suites compare plain text.

set -u

# BEGIN generated: geometry -- from conventions/geometry.yaml; do not edit
TERM_WIDTH=64         # the frame: header and footer are exactly this wide
TERM_CONTENT=62       # the widest a content line may be, ellipsis included
TERM_INDENT='   '     # 3 spaces, so a marker lands at column 4
TERM_ROW=57           # the text budget of a row: content - indent - marker
TERM_TITLE_OVERHEAD=4 # a header spends a corner, a rule, " title ", a rule
TERM_RULE=2           # columns of rule: the left corner and the right one
TERM_CONT_INDENT=8    # where a continuation starts; a constant, see the yaml

TERM_FRAME_TOP_LEFT='╭'
TERM_FRAME_TOP_RIGHT='╼'
TERM_FRAME_BOTTOM_LEFT='╰'
TERM_FRAME_BOTTOM_RIGHT='╼'
TERM_FRAME_HORIZONTAL='─'
TERM_FRAME_VERTICAL='│'
TERM_FRAME_ELLIPSIS='…'
TERM_FRAME_ELLIPSIS_COLS=1
TERM_ASCII_FRAME_TOP_LEFT='+'
TERM_ASCII_FRAME_TOP_RIGHT='+'
TERM_ASCII_FRAME_BOTTOM_LEFT='+'
TERM_ASCII_FRAME_BOTTOM_RIGHT='+'
TERM_ASCII_FRAME_HORIZONTAL='-'
TERM_ASCII_FRAME_VERTICAL='|'
TERM_ASCII_FRAME_ELLIPSIS='...'
TERM_ASCII_FRAME_ELLIPSIS_COLS=3
# END generated

TERM_RESET=''
TERM_BOLD=''

# The eight colours, empty until term_init fills them.  They are assigned here
# and not at the point of definition on purpose: an assignment at the point of
# definition runs every time the file is sourced, which is every time a tool
# starts, and a tool whose output is a pipe has to come out with no escapes in
# it.  term_init is the only thing allowed to decide there are colours.
TERM_ERROR=''
TERM_WARN=''
TERM_ADD=''
TERM_DEL=''
TERM_OK=''
TERM_NEG=''
TERM_NEUTRAL=''
TERM_TEXT=''

# The palette itself, in the 4lb-dev-dark scheme.  These are truecolour rather
# than the 16- and 256-colour approximations they used to be: #d2a6ff and
# #ffb454 have no reasonable approximation, and a tool whose error is a
# different red on two machines is not following a convention.  The block below
# is generated from conventions/tokens.yaml, which is the only place a hex is
# written down, and the hex is repeated in the comment so a value can be read
# against its token without running the generator.
#
# TERM_TEXT and TERM_NEUTRAL are the pair that carry no state: text for a body
# that is only being read, and a frame that is only saying "this is a tool
# talking".  The frame is a step quieter than the text on purpose.
#
# No shape below sets bold.  Bold is what content uses when the content is a
# heading, and a shape that forced it made every line in the box a heading.
term_palette() {
  # BEGIN generated: palette -- from data/tokens.yaml; do not edit
	TERM_ERROR=$(printf '\033[38;2;240;113;120m')   # --error            #f07178
	TERM_WARN=$(printf '\033[38;2;255;143;64m')     # --warning          #ff8f40
	TERM_ADD=$(printf '\033[38;2;74;157;205m')      # --info             #4a9dcd
	TERM_DEL=$(printf '\033[38;2;210;166;255m')     # --constant         #d2a6ff
	TERM_OK=$(printf '\033[38;2;170;217;76m')       # --success          #aad94c
	TERM_NEG=$(printf '\033[38;2;255;180;84m')      # --keyword          #ffb454
	TERM_NEUTRAL=$(printf '\033[38;2;221;221;221m') # --gray             #dddddd
	TERM_TEXT=$(printf '\033[38;2;239;239;239m')    # --foreground       #efefef
  # END generated
}

# The same eight, in the sixteen names every terminal since VT100 agrees on, for
# a terminal that cannot do 24-bit.  Same constants: TERM_ERROR is TERM_ERROR,
# and which of the two blocks filled it is term_init's decision and nobody's
# else.  A shape that picked for itself would have to be edited to work on a
# second terminal, and the edit is the kind nobody notices is missing.
#
# This is what a console gets, and it is not a fallback in the sense of "worse
# but acceptable": the eight names are the ones the palette was designed in the
# first place, and 24-bit is the refinement.  What is lost is the distinction
# between the two warm tokens, which is why `ansi:` in tokens.yaml is a name a
# person chose for each token and not the nearest of the sixteen to its hex.
term_palette_ansi() {
  # BEGIN generated: palette-ansi -- from data/tokens.yaml; do not edit
	TERM_ERROR=$(printf '\033[0;31m')   # --error      red
	TERM_WARN=$(printf '\033[0;33m')    # --warning    yellow
	TERM_ADD=$(printf '\033[0;34m')     # --info       blue
	TERM_DEL=$(printf '\033[0;35m')     # --constant   magenta
	TERM_OK=$(printf '\033[0;32m')      # --success    green
	TERM_NEG=$(printf '\033[0;36m')     # --keyword    cyan
	TERM_NEUTRAL=$(printf '\033[0;90m') # --gray       brightblack
	TERM_TEXT=$(printf '\033[0;37m')    # --foreground white
  # END generated
}

# The marker that goes with each state.  They live here rather than at the call
# sites so that a tool cannot invent a fourth way of saying "removed", and so
# that the shape and the colour cannot drift apart: term_ok uses TERM_MARK_OK
# or it is not term_ok.
#
# Generated from conventions/symbols.yaml; edit the yaml and run
# sh cli/generators/render.sh, never this block.
# BEGIN generated: markers -- from conventions/symbols.yaml; do not edit
TERM_MARK_ERROR='⟁'  # a critical failure -- the tool stopped, or the data is wrong
TERM_MARK_WARN='▽'   # important but not critical -- the tool stopped, nothing is lost
TERM_MARK_ADD='⊕'    # something was added -- a diff's left side, a file the branch lacks
TERM_MARK_DEL='⟜'    # something was removed -- a diff's right side, a file the branch has
TERM_MARK_OK='⦿'     # everything agrees, there is nothing to do
TERM_MARK_NEG='⊘'    # not fine, and not a failure either -- drift, something out of date
TERM_MARK_PLAIN='·'  # a thing happened, or a number, or a fact -- read it, no action
# END generated

# The same seven, for a terminal whose font cannot draw the ones above.
#
# A console font is a bitmap PSF holding at most 256 glyphs, and every character
# in the block above postdates the fonts themselves: the corners are Unicode 6.0
# from 2010 and the markers are from 2000.  Measured on the desktop rather than
# assumed -- of the 210 console fonts installed, the best covers 10 of the 22
# characters this repository draws, and none of them carries one of these seven.
# So there is no font to wait for, and this is not a fallback for a missing
# glyph: it is the only glyph that terminal will ever have.
#
# The two columns are told apart the same way the Unicode seven are -- by the
# reader, and not by the shape -- which they cannot be, since every ASCII
# character has the same silhouette and three of these are letters a reader will
# read as words.  symbols.md says so where the rule that forbids it is stated,
# because the alternative is a gate that is quietly wrong.
#
# Generated from the same yaml as the block above, into a separate block and
# under separate names rather than as a second half of that one: check.sh reads
# a declaration as /^TERM_MARK_[A-Z]*='/ and would read TERM_ASCII_MARK_ERROR as
# a ninth state with a name that says nothing.
#
# At file scope, not in a function, because these are the values term_vocabulary
# reads between rather than values a caller paints.  A block inside a function
# would be correct only if something called that function, and the something
# that would have to call it is the code choosing which column it wants.
# BEGIN generated: markers-ascii -- from conventions/symbols.yaml; do not edit
TERM_ASCII_MARK_ERROR='x'  # a critical failure -- the tool stopped, or the data is wrong
TERM_ASCII_MARK_WARN='!'   # important but not critical -- the tool stopped, nothing is lost
TERM_ASCII_MARK_ADD='+'    # something was added -- a diff's left side, a file the branch lacks
TERM_ASCII_MARK_DEL='-'    # something was removed -- a diff's right side, a file the branch has
TERM_ASCII_MARK_OK='o'     # everything agrees, there is nothing to do
TERM_ASCII_MARK_NEG='0'    # not fine, and not a failure either -- drift, something out of date
TERM_ASCII_MARK_PLAIN='.'  # a thing happened, or a number, or a fact -- read it, no action
# END generated

# The states that mean "look at this", as SGR prefixes.  A frame colour and a
# text colour are the same value in every one of them, which is the rule: a
# state is one colour, used on its frame and on its rows, and a shape that
# tinted them differently would be saying two things at once.
#
# Callers that need a colour can reach for these directly; they are empty
# strings when there is no terminal, which is what makes the calls below work
# unchanged either way.
term_init() {
  # The vocabulary is chosen first and before every guard, including the one
  # about stdout.  The glyphs are a property of the terminal's FONT and the
  # colour is a property of whether there is a terminal at all, and those are
  # two questions:
  #
  #   the font belongs to TERM whether or not the output is going anywhere.
  #     A tool whose output is piped on a console draws into a file that
  #     something else will read, and it should not draw `╭` there either --
  #     and it cannot, because it has no way to know what the reader has.
  #     TERM is the only evidence available and it is the right one.
  #
  #   the colour belongs to stdout.  That is the whole of the rule that
  #     piped output compares as plain text, and it is why the palette is
  #     below every guard and this is above them.
  #
  # Getting this backwards is not a subtlety.  With the vocabulary inside the
  # `-t` guard, a command on a console writes the Unicode column into a pipe,
  # because the pipe is what made it skip the choice -- and the golden files
  # in every repo compare that output, so the ASCII column is a code path
  # that no test can reach and every consumer is quietly wrong on the
  # terminal the change was written for.
  term_vocabulary
  [ -t 1 ] || return 0
  [ -z "${NO_COLOR:-}" ] || return 0
  [ "${TERM:-dumb}" != dumb ] || return 0
  TERM_RESET=$(printf '\033[0m')
  TERM_BOLD=$(printf '\033[1m')
  if term_plain; then
    term_palette_ansi
  else
    term_palette
  fi
}

# Does this terminal get the ASCII column?  One predicate, answering for the
# glyphs and the colour at once, because the two go together on every terminal
# measured: the ones that report sixteen colours are the ones whose font is a
# console font.
#
# The question is asked of `tput colors` and not of a list of TERM names, because
# the list is a guess and the count is a measurement.  It was tried the other
# way first, and the list was wrong in the direction that costs the most: it
# named `xterm` as plain, and xterm is a terminal emulator that draws Unicode
# perfectly well, so every ssh session into a machine carrying the default TERM
# would have lost its frame for nothing.  The count says 8 for xterm and 256
# for xterm-256color, and that difference is the real one.
#
# The threshold is 256 rather than "not 8", and the case in between is what
# decides it.  A terminal reporting 16 has no 24-bit but draws every glyph a
# console draws, so asking it for ASCII would throw away a frame it can render
# in order to avoid a palette it also cannot render.  Both are lost either way;
# the frame is the one a reader looks at.
#
# One predicate and not two, because a terminal that was asked for 16 colours
# and given ASCII glyphs and a terminal asked for the reverse would be two
# answers to one question, and the second one would have to be maintained by
# whoever noticed the combination looked wrong on their screen.
term_plain() {
  # `dumb`, and an unset TERM, are not a terminal that draws badly.  They
  # are a terminal that draws nothing at all -- term_init already gives them
  # no palette for exactly that reason -- and asking a box to be re-drawn in
  # ASCII for them is a second, redundant answer to a question already
  # answered.  Both keep the Unicode column, which is also what every golden
  # file in every repo records, because `env -i` leaves a shell with TERM=dumb
  # and the suite runs the tools that way.
  #
  # So the ASCII column is for terminals that draw and draw badly: TERM is
  # set to something that is not `dumb`, and it reports fewer than 256
  # colours.  That is `linux`, `vt100`, `xterm`, `screen`, and everything
  # else in that class.
  [ -z "${TERM:-}" ] && return 1
  [ "${TERM}" = dumb ] && return 1
  # No tput is not a terminal with no colours.  It is no way of finding out
  # what a terminal can do, and this function is a measurement: a
  # measurement that could not be taken is not a measurement of zero.
  #
  # The golden files found it.  Every tool's test harness in this repository
  # runs with a PATH holding exactly the programs that tool calls, and tput
  # is not among them -- so `tput colors` failed, and the failure was
  # indistinguishable from the -1 that a real terminal with no terminfo
  # entry prints.  Three tools' golden output quietly became ASCII, and the
  # gate reported it as a difference in what the tools print rather than as a
  # difference in what PATH they were given.  The fix is here and not in the
  # harness: a library that changes its output because a helper program is
  # missing from PATH is a library whose output depends on PATH.
  command -v tput >/dev/null 2>&1 || return 1
  _tp_n=$(tput colors 2>/dev/null) || _tp_n=-1
  # A TERM that is set, is not dumb, and has no terminfo entry makes tput
  # print -1.  That is the ASCII column: a name nobody can look up is a
  # terminal whose capabilities nobody can claim, and 24-bit is not something
  # to assume about it.
  case "$_tp_n" in
  '' | *[!0-9-]* | - | -1 | -2) return 0 ;;
  esac
  [ "$_tp_n" -lt 256 ] && return 0
  return 1
}

# Point every marker and every frame glyph at the column this terminal can
# draw.  A function rather than a block of assignments because there are
# fifteen of them and a caller that reached for the wrong one would be a bug
# that reproduces only on the terminal nobody tests on.
#
# The `eval` is here and not anywhere else in the file.  It is the price of
# thirteen assignments without a loop, and a loop would need the names to be
# derived from one another, at which point the mapping between a Unicode
# constant and its ASCII twin is a thing to get right once and by hand rather
# than a thing to get right in a loop body that reads better.  Nothing in this
# file uses eval for anything else, so the two lines that do are findable.
term_vocabulary() {
  # Fourteen assignments and no loop, no eval and no indirect expansion, and
  # that is the whole of the design decision.
  #
  # POSIX sh has no `${!name}` and neither does dash; zsh has `${(P)name}` and
  # neither does dash; and the only portable way to reach a variable named by
  # another is `eval`, which then has to be quoted correctly FOR EVERY SHELL
  # AT ONCE. Three versions of this function tried it. The first used
  # `${${p#*=}}` inside the eval and zsh reported `bad substitution` on every
  # pair; the second used `\$$_tv_r`, which dash evaluated to the variable's
  # NAME and zsh to its value; the third used `\${_tv_r}` and both returned
  # the name. A loop is not worth a line that is wrong in one of the two
  # shells this library is sourced by, and what it saved was fifteen short
  # assignments that `check.sh` reads back out of the generated block.
  #
  # The Unicode branch assigns every name to itself. That is not redundant:
  # it is the second half of the function, so a marker added to the generated
  # block has one place to be added to and not two that can drift.
  if term_plain; then
    TERM_MARK_ERROR=$TERM_ASCII_MARK_ERROR
    TERM_MARK_WARN=$TERM_ASCII_MARK_WARN
    TERM_MARK_ADD=$TERM_ASCII_MARK_ADD
    TERM_MARK_DEL=$TERM_ASCII_MARK_DEL
    TERM_MARK_OK=$TERM_ASCII_MARK_OK
    TERM_MARK_NEG=$TERM_ASCII_MARK_NEG
    TERM_MARK_PLAIN=$TERM_ASCII_MARK_PLAIN
    TERM_FRAME_TOP_LEFT=$TERM_ASCII_FRAME_TOP_LEFT
    TERM_FRAME_TOP_RIGHT=$TERM_ASCII_FRAME_TOP_RIGHT
    TERM_FRAME_BOTTOM_LEFT=$TERM_ASCII_FRAME_BOTTOM_LEFT
    TERM_FRAME_BOTTOM_RIGHT=$TERM_ASCII_FRAME_BOTTOM_RIGHT
    TERM_FRAME_HORIZONTAL=$TERM_ASCII_FRAME_HORIZONTAL
    TERM_FRAME_VERTICAL=$TERM_ASCII_FRAME_VERTICAL
    TERM_FRAME_ELLIPSIS=$TERM_ASCII_FRAME_ELLIPSIS
    TERM_FRAME_ELLIPSIS_COLS=$TERM_ASCII_FRAME_ELLIPSIS_COLS
  else
    TERM_MARK_ERROR=$TERM_MARK_ERROR
    TERM_MARK_WARN=$TERM_MARK_WARN
    TERM_MARK_ADD=$TERM_MARK_ADD
    TERM_MARK_DEL=$TERM_MARK_DEL
    TERM_MARK_OK=$TERM_MARK_OK
    TERM_MARK_NEG=$TERM_MARK_NEG
    TERM_MARK_PLAIN=$TERM_MARK_PLAIN
    TERM_FRAME_TOP_LEFT=$TERM_FRAME_TOP_LEFT
    TERM_FRAME_TOP_RIGHT=$TERM_FRAME_TOP_RIGHT
    TERM_FRAME_BOTTOM_LEFT=$TERM_FRAME_BOTTOM_LEFT
    TERM_FRAME_BOTTOM_RIGHT=$TERM_FRAME_BOTTOM_RIGHT
    TERM_FRAME_HORIZONTAL=$TERM_FRAME_HORIZONTAL
    TERM_FRAME_VERTICAL=$TERM_FRAME_VERTICAL
    TERM_FRAME_ELLIPSIS=$TERM_FRAME_ELLIPSIS
    TERM_FRAME_ELLIPSIS_COLS=$TERM_FRAME_ELLIPSIS_COLS
  fi
  # Set rather than mapped, because these are read by the arithmetic in
  # term_truncate and not by a shape: `...` is three columns and the unicode
  # ellipsis is one, and the number is the glyph's width and not its length
  # in bytes or in characters.
  TERM_ELLIPSIS=$TERM_FRAME_ELLIPSIS
  TERM_ELLIPSIS_COLS=$TERM_FRAME_ELLIPSIS_COLS
}

# ---------------------------------------------------------------- primitives

term_rep() { # $1 char $2 count
  _tre_c="$1"
  _tre_n="${2:-0}"
  _tre_s=''
  while [ "$_tre_n" -gt 0 ]; do
    _tre_s="$_tre_s$_tre_c"
    _tre_n=$((_tre_n - 1))
  done
  printf '%s' "$_tre_s"
}

# Cut to $2 VISIBLE characters, with the ellipsis counted inside the budget, so
# a cut line is never one column wider than the frame.  Character-based, not
# byte-based: a byte cut can land inside a glyph and print a replacement
# character where the ellipsis should be, and this machine's prompt is not
# ASCII.  ${s#?} removes one character and ${s%"$rest"} is the one it removed,
# which is the only character-at-a-time trick that is POSIX.
#
# An SGR sequence is a sequence and not a character: ESC, then parameters, then
# a final letter.  The whole of it is copied, none of it is counted, and it is
# never cut -- a cut in the middle of one leaves the terminal in that colour
# until something resets it, which is a bug in a golden file rather than a line
# in one.
#
# Counting escapes was not visible until a caller put colour in the text rather
# than in front of a marker -- a legend with two markers on one line, where the
# second is written into the first's text.  Twenty characters of escape were
# twenty characters of budget, and a legend that fitted on the page came out
# with its last word cut.
term_truncate() { # $1 text $2 max
  _ttu_s="$1"
  _ttu_max="${2:-$TERM_ROW}"
  _ttu_out=''
  _ttu_n=0
  _ttu_cut=0
  # A string that fits is not shortened, and the test is a pass of its own
  # before the loop.  Counting inside the loop cannot tell "exactly the
  # budget" from "one over the budget": both stop in the same place, and the
  # difference between them is whether a heading that fills its column
  # exactly gets an ellipsis on the end.  Two tools have a 57-character
  # column and a 57-character heading in it, and the heading was cut by a
  # character the loop had no way to see room for.
  #
  # Counting visible characters means walking the string once to measure it
  # and again to cut it, and a walk is a function.  So the measurement is
  # inline and the cut is inline too, rather than one of them being a helper
  # the other cannot reach -- a visible_length here would be the second copy
  # of the rule that decides what a character is, and the two would differ
  # on the first string with a colour in it.
  _ttu_vis=0
  while [ -n "$_ttu_s" ]; do
    _ttu_rest="${_ttu_s#?}"
    _ttu_c="${_ttu_s%"$_ttu_rest"}"
    if [ "$_ttu_c" = "$(printf '\033')" ]; then
      _ttu_s="$_ttu_rest"
      while [ -n "$_ttu_s" ]; do
        _ttu_rest="${_ttu_s#?}"
        _ttu_c="${_ttu_s%"$_ttu_rest"}"
        _ttu_s="$_ttu_rest"
        case "$_ttu_c" in
        [A-Za-z]) break ;;
        esac
      done
      continue
    fi
    _ttu_vis=$((_ttu_vis + 1))
    _ttu_s="$_ttu_rest"
  done
  if [ "$_ttu_vis" -le "$_ttu_max" ]; then
    printf '%s' "$1"
    return 0
  fi

  _ttu_s="$1"
  while [ -n "$_ttu_s" ]; do
    _ttu_rest="${_ttu_s#?}"
    _ttu_c="${_ttu_s%"$_ttu_rest"}"
    if [ "$_ttu_c" = "$(printf '\033')" ]; then
      _ttu_out="$_ttu_out$_ttu_c"
      _ttu_s="$_ttu_rest"
      # To the letter that ends it.  Another ESC ends this one and
      # starts the next, and a digit or a semicolon does not end
      # anything -- an SGR is ESC [ then numbers and ';' then a
      # letter, and stopping at the first number would count the
      # rest of the sequence as text.
      while [ -n "$_ttu_s" ]; do
        _ttu_rest="${_ttu_s#?}"
        _ttu_c="${_ttu_s%"$_ttu_rest"}"
        _ttu_out="$_ttu_out$_ttu_c"
        _ttu_s="$_ttu_rest"
        case "$_ttu_c" in
        [A-Za-z]) break ;;
        esac
      done
      continue
    fi
    # The ellipsis lives inside the budget, so a cut line is never one
    # column wider than the frame: $max characters pass and the
    # ellipsis is the next one, which means $max-1 of the string.
    # The ellipsis lives inside the budget, so a cut line is never one
    # column wider than the frame: $max characters pass and the
    # ellipsis is the next one, which means $max-1 of the string.
    #
    # One column, for the Unicode ellipsis. The ASCII one is three --
    # `...` -- and the -1 below is what makes a cut line in that column
    # two columns wider than the frame containing it, which is the one bug
    # an ASCII column introduces that a Unicode column cannot have. So the
    # ellipsis is a variable and its width comes from geometry.yaml with
    # the glyph, and the arithmetic is on the width and not on the
    # characters of the string: `…` and `...` are both one token here and
    # they are one and three columns.
    if [ "$_ttu_n" -ge "$((_ttu_max - TERM_ELLIPSIS_COLS))" ]; then
      _ttu_cut=1
      break
    fi
    _ttu_out="$_ttu_out$_ttu_c"
    _ttu_s="$_ttu_rest"
    _ttu_n=$((_ttu_n + 1))
  done
  if [ "$_ttu_cut" -eq 1 ]; then
    printf '%s%s%s' "$_ttu_out" "$TERM_ELLIPSIS" "$TERM_RESET"
    return 0
  fi
  printf '%s' "$_ttu_out"
}

# Visible column width of a marker glyph, or of a colour+marker string (a
# leading SGR sequence is skipped and not counted).  Plain (`·` / `.`) is one
# column; every other marker is two columns in the Unicode column and one
# column in the ASCII column.  term_vocabulary equates each TERM_MARK_* with
# its ASCII twin, so matching the ASCII set tells us we are in the narrow
# column.
term_marker_cols() { # $1 marker [or colour+marker] -> visible column width
  # Every marker in data/symbols.yaml is a single-column glyph; wc -L confirms
  # ⟁ ▽ ⊕ ⟜ ⦿ ⊘ · all measure as one column.  Skip a leading SGR sequence so
  # the glyph itself can be matched; the width itself is always one.
  _tmc="$1"
  case "$_tmc" in "$(printf '\033')"*)
    while [ -n "$_tmc" ]; do
      _tmc_r="${_tmc#?}"; _tmc_c="${_tmc%"$_tmc_r"}"; _tmc="$_tmc_r"
      case "$_tmc_c" in [A-Za-z]) break ;; esac
    done
  esac
  printf '1'
}

# Wrap $1 into lines of at most $2 visible columns, printing each line with
# $3 as the prefix of the first line and $4 as the prefix of every later line,
# terminated by TERM_RESET and a newline.  SGR escapes inside $1 are copied
# verbatim and never consume budget, so colour mid-text survives wrapping.
# Words break at spaces only; a single word longer than the budget is cut with
# the ellipsis (inside the budget) and occupies its own line.
term_wrap() { # $1 text $2 maxcols $3 first_prefix $4 cont_prefix
  _twr_s="$1"
  _twr_max="${2:-$TERM_ROW}"
  _twr_pfx="$3"          # prefix for the next line to print: first, then cont
  _twr_line=''
  _twr_len=0
  _twr_word=''
  _twr_wlen=0

  while [ -n "$_twr_s" ]; do
    _twr_rest="${_twr_s#?}"
    _twr_c="${_twr_s%"$_twr_rest"}"
    # SGR sequence: copy verbatim, never counted, never cut.
    if [ "$_twr_c" = "$(printf '\033')" ]; then
      _twr_word="$_twr_word$_twr_c"
      _twr_s="$_twr_rest"
      while [ -n "$_twr_s" ]; do
        _twr_rest="${_twr_s#?}"
        _twr_c="${_twr_s%"$_twr_rest"}"
        _twr_word="$_twr_word$_twr_c"
        _twr_s="$_twr_rest"
        case "$_twr_c" in [A-Za-z]) break ;; esac
      done
      continue
    fi
    case "$_twr_c" in
      ' ' | "$(printf '\t')")
        if [ -n "$_twr_word" ]; then
          _twr_add=$_twr_wlen
          if [ -n "$_twr_line" ]; then _twr_add=$((_twr_add + 1)); fi
          if [ "$((_twr_len + _twr_add))" -gt "$_twr_max" ]; then
            if [ -n "$_twr_line" ]; then
              printf '%s%s%s%s\n' "$_twr_pfx" "$_twr_line" "$TERM_RESET"
              _twr_pfx="$4"
              _twr_line=''
              _twr_len=0
            fi
            if [ "$_twr_wlen" -gt "$_twr_max" ]; then
              printf '%s%s%s%s\n' "$_twr_pfx" "$(term_truncate "$_twr_word" "$_twr_max")" "$TERM_RESET"
              _twr_pfx="$4"
            else
              _twr_line="$_twr_word"; _twr_len="$_twr_wlen"
            fi
          else
            if [ -n "$_twr_line" ]; then _twr_line="$_twr_line $_twr_word"; else _twr_line="$_twr_word"; fi
            _twr_len=$((_twr_len + _twr_add))
          fi
          _twr_word=''
          _twr_wlen=0
        fi
        ;;
      *)
        _twr_word="$_twr_word$_twr_c"
        _twr_wlen=$((_twr_wlen + 1))
        ;;
    esac
    _twr_s="$_twr_rest"
  done

  # Trailing word.
  if [ -n "$_twr_word" ]; then
    _twr_add=$_twr_wlen
    if [ -n "$_twr_line" ]; then _twr_add=$((_twr_add + 1)); fi
    if [ "$((_twr_len + _twr_add))" -gt "$_twr_max" ]; then
      if [ -n "$_twr_line" ]; then
        printf '%s%s%s%s\n' "$_twr_pfx" "$_twr_line" "$TERM_RESET"
        _twr_pfx="$4"
        _twr_line=''
        _twr_len=0
      fi
      if [ "$_twr_wlen" -gt "$_twr_max" ]; then
        printf '%s%s%s%s\n' "$_twr_pfx" "$(term_truncate "$_twr_word" "$_twr_max")" "$TERM_RESET"
        _twr_pfx="$4"
      else
        _twr_line="$_twr_word"; _twr_len="$_twr_wlen"
      fi
    else
      if [ -n "$_twr_line" ]; then _twr_line="$_twr_line $_twr_word"; else _twr_line="$_twr_word"; fi
    fi
  fi

  if [ -n "$_twr_line" ]; then
    printf '%s%s%s%s\n' "$_twr_pfx" "$_twr_line" "$TERM_RESET"
  fi
  return 0
}

# ---------------------------------------------------------------- the frame

# ╭ + ─×L + " title " + ─×R + ╼  ->  exactly TERM_WIDTH, title centred.
#
# Every glyph is a variable and the two right-hand ends are one constant, not
# two: `╭` and `╰` have their own names because they are different characters,
# and `╼` is the same character at two ends of a frame. term_vocabulary points
# them at the ASCII column when this terminal has to draw with ASCII, and
# nothing in this function has to know which it got. See TERM_FRAME_TOP_LEFT.
term_header() { # $1 frame colour $2 title $3 count ("" = no ╰╼ count line)
  _th_c="$1"
  _th_t="$2"
  _th_n="$3"
  _th_len=${#_th_t}
  _th_rest=$((TERM_WIDTH - TERM_TITLE_OVERHEAD - _th_len))
  [ "$_th_rest" -lt 2 ] && _th_rest=2
  _th_l=$((_th_rest / 2))
  _th_r=$((_th_rest - _th_l))
  printf '%s%s%s %s %s%s%s\n' \
    "$_th_c" "$TERM_FRAME_TOP_LEFT" \
    "$(term_rep "$TERM_FRAME_HORIZONTAL" "$_th_l")" "$_th_t" \
    "$(term_rep "$TERM_FRAME_HORIZONTAL" "$_th_r")" \
    "$TERM_FRAME_TOP_RIGHT" "$TERM_RESET"
  [ -n "$_th_n" ] && printf '%s%s%s %s:%s\n' \
    "$_th_c" "$TERM_FRAME_BOTTOM_LEFT" "$TERM_FRAME_BOTTOM_RIGHT" \
    "$_th_n" "$TERM_RESET"
  return 0
}

# OSC 8 hyperlink helper.
# Wraps text in an OSC 8 escape sequence so it becomes a clickable hyperlink
# in terminals that support it (most modern terminals do).
# Usage: term_hyperlink "url" "display text"
# If display text is empty, the URL itself is shown.
term_hyperlink() { # $1 = URL, $2 = display text (optional)
  _url=$1
  _text=${2:-$_url}
  # OSC 8 format: ESC ] 8 ; ; URL ST  text  ESC ] 8 ; ; ST
  # Using 7-bit ST (ESC \) for maximum compatibility
  printf '\033]8;;%s\033\\%s\033]8;;\033\\' "$_url" "$_text"
}

term_footer() { # $1 frame colour
  printf '%s%s%s%s%s\n' "$1" "$TERM_FRAME_BOTTOM_LEFT" \
    "$(term_rep "$TERM_FRAME_HORIZONTAL" $((TERM_WIDTH - TERM_RULE)))" \
    "$TERM_FRAME_BOTTOM_RIGHT" "$TERM_RESET"
}

# A titled box of plain rows.  One blank line between the rules, one before the
# box and one after the footer, which is the spacing the shell's preexec hook
# doubles up on.  The rows are the caller's to format: the library owns the
# frame, the marker and the budget, the tool owns what a row says.
#
# The accent is the whole SGR prefix of the row -- marker and text together, so
# a caller that wants the text bold says so once, here, instead of in two
# places.  An empty accent is a plain row, which is what a report wants.
term_rows_box() { # $1 frame colour $2 row accent $3 title $4 marker, then rows
  _trb_fc="$1"
  _trb_accent="$2"
  _trb_title="$3"
  _trb_marker="$4"
  shift 4
  printf '\n'
  term_header "$_trb_fc" "$_trb_title" ""
  echo ""
  for _trb_row in "$@"; do
    # indent + marker + space = 5, then up to TERM_ROW (56 + …) = 62. The
    # ellipsis sits at column 62 and the frame stays 64.  Every number there
    # is a constant and none of them is written here; the arithmetic lives in
    # data/geometry.yaml and check.sh rule D reads it back.
    #
    # The reset is unconditional, so a row whose accent is empty still
    # ends with one. That is four bytes a hand-written plain row need not
    # have printed; see data/docs/output.md under Colour. Closing what was opened is
    # not worth a branch that has to be right on every call, and a plain
    # row inheriting the terminal's existing colour is the bug it stops.
    if [ -z "$_trb_row" ]; then
      printf '%s%s%s %s%s\n' "$TERM_INDENT" "$_trb_accent" "$_trb_marker" "" "$TERM_RESET"
      continue
    fi
    _trb_cols=$(term_marker_cols "$_trb_marker")
    _trb_pad=$((_trb_cols + 1))
    _trb_firstpfx="$TERM_INDENT$_trb_accent$_trb_marker "
    _trb_contpfx="$TERM_INDENT$_trb_accent$(term_rep ' ' "$_trb_pad")"
    term_wrap "$_trb_row" "$TERM_ROW" "$_trb_firstpfx" "$_trb_contpfx"
  done
  echo ""
  term_footer "$_trb_fc"
  printf '\n'
  return 0
}

# The same box, with the rows in a file rather than in the argument list.
#
# This exists because a consumer found most of its rows while it walked, and a
# POSIX sh cannot hand twenty rows over as "$@" -- there is no array, so a list
# has to be a file and a while loop.  That consumer had two choices: build the
# rows into a file and draw them itself, or build them into a file and ask the
# library to draw them.  It did the first, for a long time, and the cost was
# thirty lines of the library's arithmetic living in another repository: the
# indent, the marker, the budget and the blank lines around the frame.  A change
# to the frame in this file would not have reached them, and the only way anyone
# would find out was to compare the two by eye.
#
# A leading tab marks a continuation: that line has no marker of its own and is
# printed under the row it belongs to, aligned with that row's text.  The tab is
# the marker because no row a caller writes begins with one, and the file is the
# caller's scratch space, so the convention is stated here rather than assumed.
term_rows_box_file() { # $1 frame colour $2 row accent $3 title $4 marker $5 path
  _trbf_fc="$1"
  _trbf_accent="$2"
  _trbf_title="$3"
  _trbf_marker="$4"
  _trbf_path="$5"
  [ -s "$_trbf_path" ] || return 0
  printf '\n'
  term_header "$_trbf_fc" "$_trbf_title" ""
  echo ""
  while IFS= read -r _trbf_row; do
    case "$_trbf_row" in
    "$(printf '\t')"*)
      # A continuation. The tab is the marker, and what is left is
      # printed under the row above and cut by the same budget, so a
      # reason too long for the frame is cut once and in one place rather
      # than per shape.
      #
      # The indent is a constant and not an alignment, and the reason is
      # worth writing down because it looks like a bug. Rows in these
      # files are `label  value`: the label is six to fourteen characters
      # and the value follows, so the text of a row is at a different
      # column every time. A continuation cannot line up with a row's text
      # because there is no single column for it to line up with.
      #
      # What it does instead is sit a little further right than the frame's
      # own indent and further left than most values, which reads as
      # belonging to the row above without claiming to be part of it. The
      # engine that called this spent its own arithmetic getting that
      # offset right and it was a literal there; here it is a number in
      # geometry.yaml, and a change to it is a change in one place.
      _trbf_row=${_trbf_row#$(printf '\t')}
      _trbf_pfx=$(term_rep ' ' "$TERM_CONT_INDENT")
      term_wrap "$_trbf_row" "$TERM_ROW" "$_trbf_pfx" "$_trbf_pfx"
      ;;
    *)
      if [ -z "$_trbf_row" ]; then
        printf '%s%s%s %s%s\n' "$TERM_INDENT" "$_trbf_accent" "$_trbf_marker" "" "$TERM_RESET"
        continue
      fi
      _trbf_cols=$(term_marker_cols "$_trbf_marker")
      _trbf_pad=$((_trbf_cols + 1))
      _trbf_firstpfx="$TERM_INDENT$_trbf_accent$_trbf_marker "
      _trbf_contpfx="$TERM_INDENT$_trbf_accent$(term_rep ' ' "$_trbf_pad")"
      term_wrap "$_trbf_row" "$TERM_ROW" "$_trbf_firstpfx" "$_trbf_contpfx"
      ;;
    esac
  done <"$_trbf_path"
  echo ""
  term_footer "$_trbf_fc"
  printf '\n'
  return 0
}

# ── a box with a question in it ──────────────────────────────────────────────
#
# Every other box in this file is drawn in one call: header, rows, footer.  That
# is right for all of them and wrong for the one a tool asks a question inside,
# because the answer belongs on the prompt's own line and the frame closes after
# it.  A caller that wants that had two ways and both were bad: draw the box
# itself, which is thirty lines of this file's arithmetic copied into another
# repository -- exactly what term_rows_box_file exists to end -- or close the
# frame first and let the answer land below the bottom edge, which puts the
# question and its answer in two different places.
#
# So the box is opened, drawn and left open, and closed once the caller has read
# the answer.  The reader's own terminal echoes the character they type onto the
# prompt's line, so nothing here draws the answer and nothing moves a cursor.
#
# The rows are this file's own line: its indent, its marker, its budget, its
# reset, and the colour from term_marker_color, which is where a marker's colour
# has always come from.  A caller that hardcodes a colour for one of these rows
# loses the palette, and did.

term_ask_open() { # term_ask_open <title>
  printf '\n'
  term_header "$TERM_NEUTRAL" "$1" ""
  printf '\n'
  return 0
}

# One row of an open box.  <marker> is a marker glyph, an empty marker or a
# single space for a plain line, or '-' for the frame's rule.
term_ask_row() { # term_ask_row <marker> <row> [--stderr]

  # If TERM_ASK_NO_NEWLINE is set, the row is printed without a trailing

  # newline. This is used for the prompt so the cursor stays on the line

  # for read. The caller sets TERM_ASK_NO_NEWLINE=1 before the prompt row

  # and unsets it after.

  # If the third argument is --stderr, write to stderr (unbuffered) so the

  # prompt appears immediately before read(1) is called.

  _term_ask_nl='
'
  [ -n "${TERM_ASK_NO_NEWLINE:-}" ] && _term_ask_nl=''

  _term_ask_fd=1
  case "${3:-}" in

  --stderr) _term_ask_fd=2 ;;

  esac

  # TERM_ASK_INDENT, when set, replaces the frame's indent: the prompt hangs

  # under its question rather than sitting beside it.

  # ${#$_var} is not POSIX, so the length is taken from the variable that was
  # set rather than from the local holding it.
  _term_ask_indent="$TERM_INDENT"
  _term_ask_len=${#TERM_INDENT}
  if [ -n "${TERM_ASK_INDENT:-}" ]; then
    _term_ask_indent="$TERM_ASK_INDENT"
    _term_ask_len=${#TERM_ASK_INDENT}
  fi

  case "$1" in

  -)

    # The rule, at the frame's own width: indent, dashes, reset.  The same

    # three parts term_status's rule case prints, and for the same reason --

    # a rule narrower than the frame above it reads as a typo rather than as

    # a divider.

    printf '%s%s%s%s%s' "$_term_ask_indent" "$TERM_NEUTRAL" \
      "$(term_rep "$TERM_FRAME_HORIZONTAL" \
        $((TERM_WIDTH - TERM_RULE - _term_ask_len)))" "$TERM_RESET" "$_term_ask_nl" >&"$_term_ask_fd"
    ;;

  '' | ' ')
    # A blank row is a blank line and not a row with nothing on it.  It used
    # to be one, which is TERM_INDENT plus the marker's two columns plus a
    # reset ending nothing: trailing whitespace in every confirmation box,
    # and an amber space, because a space is not in the marker vocabulary
    # and term_marker_color's fallback painted it.  Golden files record those
    # bytes and a reader cannot see them.
    if [ -z "$2" ]; then
      printf '%s' "$_term_ask_nl" >&"$_term_ask_fd"
      return 0
    fi

    # Text with no glyph: no marker, and no marker's space either, so the
    # words start in the column the text of every other row starts in.
    if [ -n "${TERM_ASK_NO_NEWLINE:-}" ]; then
      printf '%s%s%s%s' "$_term_ask_indent" "$TERM_NEUTRAL" \
        "$(term_truncate "$2" $((TERM_WIDTH - _term_ask_len)))" "$TERM_RESET" "$_term_ask_nl" >&"$_term_ask_fd"
    else
      _tak_pfx="$_term_ask_indent$TERM_NEUTRAL"
      term_wrap "$2" $((TERM_WIDTH - _term_ask_len)) "$_tak_pfx" "$_tak_pfx" >&"$_term_ask_fd"
    fi
    ;;

  *)

    _tak_color=$(term_marker_color "$1")
    _tak_cols=$(term_marker_cols "$_tak_color$1")
    _tak_pad=$((_tak_cols + 1))
    _tak_firstpfx="$_term_ask_indent$_tak_color$1 "
    _tak_contpfx="$_term_ask_indent$_tak_color$(term_rep ' ' "$_tak_pad")"
    if [ -n "${TERM_ASK_NO_NEWLINE:-}" ]; then
      printf '%s%s%s %s%s%s' "$_term_ask_indent" "$_tak_color" "$1" \
        "$(term_truncate "$2" "$TERM_ROW")" "$TERM_RESET" "$_term_ask_nl" >&"$_term_ask_fd"
    else
      term_wrap "$2" "$TERM_ROW" "$_tak_firstpfx" "$_tak_contpfx" >&"$_term_ask_fd"
    fi
    ;;

  esac

  return 0

}

term_ask_close() {
  printf '\n'
  term_footer "$TERM_NEUTRAL"
  printf '\n'
  return 0
}

# ── standardised confirmation prompt ───────────────────────────────────────────
#
# A reusable prompt box with the shape:
#
#   ╭────────────────────────── [title] ─────────────────────────╼
#
#      [what is about to happen to this list]
#
#      ⊕ [what will be deleted, added]
#      · [the list, and the consequences]
#
#      ─────────────────────────────────────────────────────────
#      · [summary of the change, done if confirmed]
#
#      · [the question]
#        · answer [y/N]: [cursor waits here]
#
#   ╰────────────────────────────────────────────────────────────╼
#
# Every gap in it is a genuinely empty line.  The rows that used to stand in
# for one -- TERM_INDENT, a marker's two columns and a reset, on a row with
# nothing on it -- were trailing whitespace in every box, and a space marker is
# not in the vocabulary, so term_marker_color's fallback painted those lines
# amber.  term_alert and term_status make a blank advice line a blank line for
# the same reason, and this is the third place that has to be told.
#
# The prompt hangs under its question, two columns in, and it is the only row
# printed without its newline: the cursor stays after "answer [y/N]: " and the
# character the reader types appears there.  A prompt that ends its line and
# waits on the next one asks a question the reader has to find.
#
# The caller provides:
#   $1 = title in the header; empty means the generic "Action needed", which a
#        caller overrides only when it has something more specific to say
#   $2 = one line saying what is about to happen to the list below it
#   $3 = the question, above the prompt
#   $4 = path to a file of rows, one per line, format: marker<TAB>text
#   $5 = summary of what confirming does
#
# Returns: 0 if user answered y/Y, 1 otherwise (or on EOF/Ctrl-D)
term_confirm() { # term_confirm <title> <info> <question> <rows-file> <summary>
  [ $# -eq 5 ] || return 1

  _tc_title="$1"
  [ -n "$_tc_title" ] || _tc_title='action required'
  _tc_info="$2"
  _tc_question="$3"
  _tc_rows_file="$4"
  _tc_summary="$5"

  [ -r "$_tc_rows_file" ] || return 1

  term_ask_open "$_tc_title"

  term_ask_row '' "$_tc_info"
  term_ask_row '' ''

  while IFS="$(printf '\t')" read -r _tc_marker _tc_text ||
    [ -n "$_tc_marker$_tc_text" ]; do
    term_ask_row "$_tc_marker" "$_tc_text"
  done <"$_tc_rows_file"

  term_ask_row '' ''
  term_ask_row '-' ''

  term_ask_row "$TERM_MARK_PLAIN" "$_tc_summary"
  term_ask_row '' ''
  term_ask_row "$TERM_MARK_PLAIN" "$_tc_question"

  # To stderr when stdout is not a terminal.  A prompt is the one row with
  # no newline on it, so on a pipe it sits in stdio's buffer while read(2)
  # waits on the terminal for an answer to a question nobody has seen yet.
  # fd 2 is unbuffered, and the box around it has already been printed.
  _tc_prompt_stderr=''
  [ -t 1 ] || _tc_prompt_stderr='--stderr'
  TERM_ASK_NO_NEWLINE=1 TERM_ASK_INDENT="$TERM_INDENT  " \
    term_ask_row "$TERM_MARK_PLAIN" 'answer [y/N]: ' "$_tc_prompt_stderr"
  unset TERM_ASK_NO_NEWLINE TERM_ASK_INDENT

  _tc_answer=''
  IFS= read -r _tc_answer

  printf '\n'
  term_footer "$TERM_NEUTRAL"
  printf '\n'

  case "$_tc_answer" in
  y | Y | yes | YES | Yes) _tc_rc=0 ;;
  *) _tc_rc=1 ;;
  esac

  return "$_tc_rc"
}

# ── the six states ───────────────────────────────────────────────────────────
#
# Each of the six is one colour, used on its frame, its marker and its rows, so
# that the shape alone says what happened before a word is read.  A box that
# tinted the frame one way and the text another was spending two colours to say
# one thing, and the second one was decoration.

# Something happened, or was confirmed, and there is nothing to act on: the
# file was edited, a command reported success, a check passed.  The quietest of
# the six, and the one that has to stay quietest -- a confirmation that shouts
# is a confirmation nobody reads.
term_notice_state() { # $1 frame colour $2 row accent $3 marker $4 message
  _tns_c="$1"
  _tns_accent="$2"
  printf '\n'
  printf '%s%s%s%s%s\n' "$_tns_c" "$TERM_FRAME_TOP_LEFT" \
    "$(term_rep "$TERM_FRAME_HORIZONTAL" $((TERM_WIDTH - TERM_RULE)))" \
    "$TERM_FRAME_TOP_RIGHT" "$TERM_RESET"
  echo ""
  # Every line of the message, and none of them cut.
  #
  # It used to truncate, and that was wrong in the way a truncation is always
  # wrong: the message is prose, and prose here has paragraphs in it.  A
  # notice that ends mid-sentence in the middle of the frame is not a
  # shorter notice, it is a notice whose last word is missing, and the
  # reader cannot tell which word.  term_alert has never truncated for the
  # same reason and a library with two renderers disagreeing about whether
  # prose survives is a library with a bug in it.
  #
  # The marker goes on the first line and the rest line up under it, which
  # is what term_alert does for the same reason: a hand-formatted block
  # keeps its own alignment instead of starting again at column 1.
  _tn_cols=$(term_marker_cols "$3")
  _tn_pad=$((_tn_cols + 1))
  _tn_firstpfx="$TERM_INDENT$_tns_accent$3 "
  _tn_contpfx="$TERM_INDENT$_tns_accent$(term_rep ' ' "$_tn_pad")"
  printf '%s' "$4" | (
    _tn_started=0
    while IFS= read -r _tn_line || [ -n "$_tn_line" ]; do
      if [ -z "$_tn_line" ]; then
        printf '\n'
        continue
      fi
      if [ "$_tn_started" -eq 0 ]; then
        term_wrap "$_tn_line" "$TERM_ROW" "$_tn_firstpfx" "$_tn_contpfx"
        _tn_started=1
      else
        term_wrap "$_tn_line" "$TERM_ROW" "$_tn_contpfx" "$_tn_contpfx"
      fi
    done
  )
  echo ""
  term_footer "$_tns_c"
  printf '\n'
  return 0
}

# A confirmation that a specific thing happened, rather than that something did.
# Same shape as a notice, in the state the fact belongs to -- a line appended is
# an addition and not merely an occurrence, so it gets the added marker and the
# colour that goes with it.  A neutral notice for it said "something happened",
# which is the one thing the vocabulary has a better word for.
# The frame colour and the row accent are two arguments and not one, and the
# gap is the neutral one.  A notice carries TERM_NEUTRAL on its frame and
# nothing at all on its row: the state that has no news has no business being
# painted, and a row that opened with the frame's grey read as a state rather
# than as a tool talking.  alias-manager's self-test asserts the plain row is a
# bare reset, and it is right to -- that test caught this being got wrong.
term_notice() { term_notice_state "$TERM_NEUTRAL" '' "$TERM_MARK_PLAIN" "$1"; }
term_added() { term_notice_state "$TERM_ADD" "$TERM_ADD" "$TERM_MARK_ADD" "$1"; }
term_removed() { term_notice_state "$TERM_DEL" "$TERM_DEL" "$TERM_MARK_DEL" "$1"; }

# Everything agrees.  This is the only green box in the vocabulary, and it says
# one thing: there is no work to do.  A tool that painted something else green
# would make this box the one a reader learned to skip.
term_ok() { # $1 title $2 message
  term_rows_box "$TERM_OK" "$TERM_OK" "$1" "$TERM_MARK_OK" "$2"
}

# Not fine, and not a failure either: there is drift, or something is out of
# date, and the tool is reporting it rather than refusing.  Yellow is the only
# state between the two ends, and a tool should reach for it when the honest
# answer is "look at this" and not "I stopped".
term_bad() { # $1 title $2 message
  term_rows_box "$TERM_NEG" "$TERM_NEG" "$1" "$TERM_MARK_NEG" "$2"
}

# A report, not a state: the numbers, the names, the facts.  Neutral frame,
# plain rows, and the plain marker -- a report is not saying anything is wrong.
#
# Rows come in (marker, row) pairs so that one of them can be a state.  A
# status that finds drift has exactly one interesting line, and the honest
# place to say so is that line: colouring the whole box yellow would have made
# the three rows that are merely counts look like part of the news.  An empty
# marker is the plain one, so the common case reads as an empty string rather
# than as a name nobody has heard of.
#
# A bare marker is printed in TERM_NEG, which is the one state a plain
# "something is not right" marker can mean.  A marker that already carries a
# colour is passed through with nothing added, and that is the whole reason a
# caller colours a marker itself: a report whose rows are results -- one
# skipped, one failed, one built, all in the same box -- cannot say which is
# which if the library picks.  The test is for an escape in the string, not
# for a leading one, so a caller that wraps its own prefix still counts.
#
# Two rows of a table are not states and carry no glyph: its column header, and
# the rules under the header and under the rows.  They are the box describing
# itself, not the box reporting something, and putting a marker there would
# claim a state for a line that has none.  They are recognised by the marker
# rather than by a name -- dashes, or spaces and nothing else -- which is what
# lets a caller pass the obvious thing and get the right row.  Neither has a
# constant in the marker vocabulary, deliberately: check.sh rule F counts every
# TERM_MARK_* as vocabulary and rule B would then demand a colour for a row
# that has none, and the absence of a state is not a state.
# Map a marker to its state color.  The marker vocabulary is the
# single source of truth; this function is the only place that knows
# which colour goes with which glyph.
term_marker_color() { # $1 = marker glyph; prints the colour SGR
  case "$1" in
  "$TERM_MARK_ERROR") printf '%s' "$TERM_ERROR" ;;
  "$TERM_MARK_WARN") printf '%s' "$TERM_WARN" ;;
  "$TERM_MARK_ADD") printf '%s' "$TERM_ADD" ;;
  "$TERM_MARK_DEL") printf '%s' "$TERM_DEL" ;;
  "$TERM_MARK_OK") printf '%s' "$TERM_OK" ;;
  "$TERM_MARK_NEG") printf '%s' "$TERM_NEG" ;;
  "$TERM_MARK_PLAIN") printf '%s' "$TERM_NEUTRAL" ;;
  *) printf '%s' "$TERM_NEG" ;; # fallback
  esac
}

term_status() { # $1 title, then (marker, row) pairs; "" = the plain marker
  _ts_title="$1"
  shift
  printf '\n'
  term_header "$TERM_NEUTRAL" "$_ts_title" ""
  echo ""
  while [ $# -gt 0 ]; do
    case "$1" in
    # Furniture.  A rule is not a row: no glyph, it starts at the
    # indent so it can reach the right edge, and it gets the frame's
    # whole width rather than the text column's 57.  A rule
    # indented into the text column stops two characters short of
    # everything above it and reads as a mistake.
    -*)
      printf '%s%s%s%s\n' "$TERM_INDENT" "$TERM_NEUTRAL" \
        "$(term_truncate "$2" \
          $((TERM_WIDTH - 2 - ${#TERM_INDENT})))" \
        "$TERM_RESET"
      ;;
    '')
      # A plain row is a bare reset: the frame may be neutral, but the row
      # itself carries no colour (term_notice_state does the same).
      _ts_m="$TERM_MARK_PLAIN"
      _ts_cols=$(term_marker_cols "$_ts_m")
      _ts_pad=$((_ts_cols + 1))
      _ts_firstpfx="$TERM_INDENT$_ts_m "
      _ts_contpfx="$TERM_INDENT$(term_rep ' ' "$_ts_pad")"
      term_wrap "$2" "$TERM_ROW" "$_ts_firstpfx" "$_ts_contpfx"
      ;;
    # Has a glyph, or has colour.  A colour is the caller's own and
    # is passed through with nothing added: a second colour would
    # be a lie about whose choice this is.
    *[![:space:]]*)
      if case "$1" in *"$(printf '\033')"*) true ;; *) false ;; esac then
        # Already coloured by the caller; pass through.  $1 is colour+glyph;
        # the glyph is one character, so stripping the last char yields the
        # colour prefix alone for the continuation indent.
        _ts_m="$1"
        _ts_c0="${_ts_m%?}"
        _ts_cols=$(term_marker_cols "$_ts_m")
        _ts_pad=$((_ts_cols + 1))
        _ts_firstpfx="$TERM_INDENT$_ts_m "
        _ts_contpfx="$TERM_INDENT$_ts_c0$(term_rep ' ' "$_ts_pad")"
        term_wrap "$2" "$TERM_ROW" "$_ts_firstpfx" "$_ts_contpfx"
      else
        _ts_color=$(term_marker_color "$1")
        # Colour and marker as two arguments rather than one glued
        # together: the format has five conversions, and feeding it four
        # put the space that separates a marker from its text after the
        # text instead, so a row read as marker and words in one token.
        _ts_m="$_ts_color$1"
        _ts_cols=$(term_marker_cols "$_ts_m")
        _ts_pad=$((_ts_cols + 1))
        _ts_firstpfx="$TERM_INDENT$_ts_m "
        _ts_contpfx="$TERM_INDENT$_ts_color$(term_rep ' ' "$_ts_pad")"
        term_wrap "$2" "$TERM_ROW" "$_ts_firstpfx" "$_ts_contpfx"
      fi
      ;;
    # Spaces and nothing else: no glyph, and still a row of text.
    # The header line of a table is this -- it describes the box
    # rather than reporting a result, so it is not a state -- and
    # it keeps the two columns a marker and its space would have
    # taken, so its text lands where every other row's does.
    #
    # Tested on the marker instead of on a name, and that is the
    # whole reason it works: a caller writing a literal space here
    # gets this row rather than falling through to the branch above
    # and printing an amber space in column 4.  A sentinel constant
    # would have had to be compared by value, and the one thing it
    # could not do is stop a literal from being wrong quietly.
    *)
      _ts_pfx="$TERM_INDENT  "
      term_wrap "$2" "$TERM_ROW" "$_ts_pfx" "$_ts_pfx"
      ;;
    esac
    shift 2
  done
  echo ""
  term_footer "$TERM_NEUTRAL"
  printf '\n'
  return 0
}

# ---------------------------------------------------------------- columns
#
# Two columns, for a list whose entries are short and whose count is not.
#
# This is not a table.  A table has aligned columns of different data -- a
# name, a count, a size -- and directory-pdf's is the one in this catalog.  This is
# one list read down rather than across, and the only thing it changes about a
# row is that there is a second one beside it.  So it takes term_status's frame
# and term_status's marker vocabulary and gives the rows an arrangement.
#
# The arithmetic comes from this file's own numbers rather than from a constant
# typed next to them:
#
#   the text budget is the frame, less its two end characters, less the
#   indent, less the marker and its space:  64 - 2 - 3 - 2 = 57
#   two cells and the gap between them divide it:
#     (57 - 3) / 2 = 27 per cell, less the marker and its space, is 25
#
# The gap is 3 because 57 minus 3 is even.  A gap of 2 and a gap of 4 both buy
# the same odd remainder and spend it on one column, which is how a layout ends
# up with a wide column beside a narrow one that nobody chose.  With this one
# the second column's marker lands at column 34 -- the first past the middle of
# a 62-wide line -- so the two read as halves of it rather than as one column
# with something parked on the right.
#
# **Down the columns, not across the rows.**  Across, row i is item i beside
# item i+1, and the caller's order interleaves with itself: the sections of a
# package list become `git curl zsh zoxide` beside `zoxide nvim helix`, which
# looks deliberate and is not.  Down, the order reads top to bottom in the
# first column and continues in the second, so a list that is grouped stays
# grouped.  It costs the writer having to mean it, and nothing else.
#
# A rule ends the columns rather than being one.  Everything under a rule is
# what the list adds up to -- counts, a verdict -- and those are sentences and
# not entries: two of them side by side is two sentences running into each
# other, and they are long enough that the pair would not fit the frame anyway.
# So the rule says "the list is over", and what follows is one row each, which
# is what term_status would have printed for it.
#
# A cell too wide for one column takes the whole row rather than being cut.
# The names that reach a cell are the ones a reader is going to act on, and a
# package name cut in half at the ellipsis is a name that cannot be installed.
#
# There is no header row, and that is a boundary rather than an omission.  A
# header describes columns, and this has none to describe: it is one list, and
# the box's title is what describes it.  A caller whose rows are a column per
# datum, and who wants a row naming them, wants term_status.
term_columns() { # $1 title, then (marker, text) pairs
  _tc_title=$1
  shift

  # Named rather than inlined because a caller wanting a third column
  # changes one number here and the arithmetic below still holds.
  _tc_cols=2
  _tc_gap=3
  _tc_budget=$((TERM_WIDTH - 2 - ${#TERM_INDENT} - 2))
  _tc_cell=$(((_tc_budget - _tc_gap * (_tc_cols - 1)) / _tc_cols - 2))

  _tc_nl='
'
  _tc_all=''
  _tc_end=''
  _tc_state=0
  _tc_n=0

  # One pass, two lists: everything before the first rule is the list, and
  # everything from the rule on is its tally.  A record cannot contain a
  # newline, so the newline is a separator that cannot collide with one.
  #
  # _tc_end is never anything but the tally.  The splitting below runs
  # term_columns_pop, whose scratch is called _tc_pop_rest, and a tally
  # that shared a name with it was emptied by the first pop -- which is
  # why there are two names and only two.
  while [ $# -gt 0 ]; do
    case "$1" in -*) _tc_state=1 ;; esac
    if [ "$_tc_state" -eq 0 ]; then
      _tc_all=$_tc_all$_tc_nl$1$'\t'$2
      _tc_n=$((_tc_n + 1))
    else
      _tc_end=$_tc_end$_tc_nl$1$'\t'$2
    fi
    shift 2
  done
  _tc_all=${_tc_all#$_tc_nl}
  _tc_end=${_tc_end#$_tc_nl}

  # How deep each column is.  Counted in the pass above rather than from
  # $# here: the first _tc_rows records go left and the rest go right, so
  # the count has to be of the list and not of the arguments -- and
  # grep -c on an empty list prints 0 and exits 1, which a `|| echo 0`
  # turns into two zeroes and an arithmetic error.
  _tc_rows=$(((_tc_n + _tc_cols - 1) / _tc_cols))

  # The split.  _tc_src ends up holding whatever the left column did not
  # take, which is the right column, so nothing is indexed twice.
  _tc_left=''
  _tc_src=$_tc_all
  _tc_i=0
  while [ "$_tc_i" -lt "$_tc_rows" ] && [ -n "$_tc_src" ]; do
    term_columns_pop "$_tc_src"
    _tc_src=$_tc_pop_rest
    if [ -z "$_tc_left" ]; then
      _tc_left=$_tc_pop_head
    else
      _tc_left=$_tc_left$_tc_nl$_tc_pop_head
    fi
    _tc_i=$((_tc_i + 1))
  done
  _tc_right=$_tc_src

  printf '\n'
  term_header "$TERM_NEUTRAL" "$_tc_title" ''
  echo ""

  # The grid: a record from each column, and one row for the pair.
  _tc_src=$_tc_left
  while [ -n "$_tc_src" ]; do
    term_columns_pop "$_tc_src"
    _tc_a=$_tc_pop_head
    _tc_src=$_tc_pop_rest
    _tc_b=''
    if [ -n "$_tc_right" ]; then
      term_columns_pop "$_tc_right"
      _tc_b=$_tc_pop_head
      _tc_right=$_tc_pop_rest
    fi
    term_columns_cell "$_tc_a" "$_tc_b"
  done

  # The tally, one row each.
  _tc_src=$_tc_end
  while [ -n "$_tc_src" ]; do
    term_columns_pop "$_tc_src"
    _tc_tally=$_tc_pop_head
    _tc_src=$_tc_pop_rest
    term_columns_row "$_tc_tally"
  done

  echo ""
  term_footer "$TERM_NEUTRAL"
  printf '\n'
  return 0
}

# Split a list of records at its first newline: _tc_pop_head is the first record
# and _tc_pop_rest is the rest of the list.
#
# Globals rather than a returned value, because POSIX sh has no `local` and this
# file uses prefixed globals for that reason rather than in preference to it.
# Both are overwritten by every call, so a caller copies the one it wants before
# calling again.
term_columns_pop() {
  case "$1" in
  *"$_tc_nl"*)
    _tc_pop_head=${1%%$_tc_nl*}
    _tc_pop_rest=${1#*$_tc_nl}
    ;;
  *)
    _tc_pop_head=$1
    _tc_pop_rest=''
    ;;
  esac
  return 0
}

# One row of the grid.  $1 is a record and $2 the record beside it, or empty
# when the second column has run out.
term_columns_cell() { # <record> [<record>]
  _tcc_at=${1#*$'\t'}
  if [ -z "$2" ]; then
    term_columns_row "$1"
    return 0
  fi
  _tcc_am=${1%%$'\t'*}
  _tcc_bm=${2%%$'\t'*}
  _tcc_bt=${2#*$'\t'}
  # Too wide to sit beside anything.  The names that get here are the ones
  # a reader came for, and half of one is not a name anybody can install.
  if [ "${#_tcc_at}" -gt "$_tc_cell" ] || [ "${#_tcc_bt}" -gt "$_tc_cell" ]; then
    term_columns_row "$1"
    term_columns_row "$2"
    return 0
  fi
  printf '%s%s %s' "$TERM_INDENT" "$_tcc_am" "$_tcc_at"
  term_columns_spaces $((_tc_cell - ${#_tcc_at} + _tc_gap))
  # No padding after the second cell: it ends the row, and spaces after
  # the last thing on a line are invisible anyway.
  printf '%s %s%s\n' "$_tcc_bm" "$_tcc_bt" "$TERM_RESET"
  return 0
}

# One row in one cell, at the frame's whole width.
#
# A rule has no glyph and starts at the indent, because furniture takes the
# frame's width: a rule indented into the text column stops short of everything
# above it and reads as a mistake rather than as a divider.  Anything else is a
# row with a marker and gets the marker's two columns, which is what
# term_status gives it too.
term_columns_row() { # <record>
  _tcr_m=${1%%$'\t'*}
  _tcr_t=${1#*$'\t'}
  case "$_tcr_m" in
  -*)
    # A rule with no text is a blank line, and a blank line is the one
    # thing a caller cannot draw: every other row in here carries a
    # glyph or a word, and a row of indent plus a space is trailing
    # whitespace that a golden file records and a reader cannot see.
    # A list that needs air before its own tally asks for it this way.
    [ -n "$_tcr_t" ] || {
      printf '\n'
      return 0
    }
    # Not truncated, and this is the one row in the file that is not.  A
    # rule is furniture: it is asked for at the frame's exact width, and
    # a rule that came back one character short with an ellipsis on the
    # end is not a rule that was too long, it is a rule that was broken.
    # A rule long enough to need cutting is a caller's arithmetic, and
    # the frame's own right edge is where it stops.
    printf '%s%s%s%s\n' "$TERM_INDENT" "$TERM_NEUTRAL" \
      "$_tcr_t" "$TERM_RESET"
    return 0
    ;;
  esac
  printf '%s%s %s%s\n' "$TERM_INDENT" "$_tcr_m" \
    "$(term_truncate "$_tcr_t" $((TERM_WIDTH - 2 - ${#TERM_INDENT} - 2)))" \
    "$TERM_RESET"
  return 0
}

# $1 spaces.  A named copy because a positional parameter is not assignable in
# POSIX sh: `1=$(( 1 - 1 ))` is not a decrement, it is a command named `1=0`,
# and it fails every time and never ends the loop.
term_columns_spaces() {
  _tcs=$1
  while [ "$_tcs" -gt 0 ]; do
    printf ' '
    _tcs=$((_tcs - 1))
  done
  return 0
}

# ------------------------------------------------------------------ pairs
#
# Two fields side by side, every row aligned: a name and what it does, a key
# and where it points, an alias and the command it stands for.
#
# This is the other half of what term_columns is, and the two are not the same
# thing.  term_columns has *one* list and puts a second entry beside each of its
# own entries -- one field per row, wrapped down the columns.  This has *two*
# fields per row, and every row is a different pair of them.  A list cannot be
# made to do this and a pair cannot be made to do that, so they are two
# functions rather than one function with a switch: a caller that has one list
# should not be offered a mode that silently drops the second field, and a
# caller that has pairs should not have to know that "columns" means "fields".
#
# directory-pdf's results box is this shape and builds it out of the frame
# primitives by hand.  It predates this function and is not rewritten to use
# it: its columns are five, they are sized to their data, and it prints a
# per-column rule under a header -- all of which is more than this does.
#
# **The caller gives the first column's width, not both.** The second column
# gets what is left, which is the only arrangement that cannot be wrong: a
# function asked for two widths and handed a pair that does not add up would
# have to choose which one to believe, and it would choose silently.  The gap
# is the same 3 term_columns uses, and for the same reason -- 57 minus 3 is
# even, so neither column is a character narrower than it needn't be.
#
# The markers are term_status's, recognised by shape for the same reason and by
# the same table:
#
#   a glyph    a row, in the colour the caller sent
#   spaces     a header: no glyph, and the two columns named
#   dashes     a rule: no glyph, the frame's whole width
#
# A header is honest here and is not in term_columns, and that is the whole
# difference between the two: this has two columns of different data, so naming
# them says what a reader would otherwise have to guess.
term_pairs() { # $1 title, $2 first column's width, then (marker, left, right)
  _tp_title=$1
  _tp_left=$2
  shift 2

  _tp_gap=3
  _tp_budget=$((TERM_WIDTH - 2 - ${#TERM_INDENT} - 2))
  _tp_right=$((_tp_budget - _tp_gap - _tp_left))

  printf '\n'
  term_header "$TERM_NEUTRAL" "$_tp_title" ''
  echo ""
  while [ $# -gt 0 ]; do
    # Dispatched on the marker before the third field is read, because a
    # rule is a marker and a text and has no third field -- the same
    # arity a rule has everywhere else in this file.  Reading $3 first
    # would make the rule a triple whose last field had to be passed and
    # ignored, which is a field a caller cannot forget to pass and
    # cannot see the reason for.
    case "$1" in
    -*) term_pairs_rule "$2" ;;
    *) term_pairs_row "$1" "$2" "$3" ;;
    esac
    case "$1" in
    -*) shift 2 ;;
    *) shift 3 ;;
    esac
  done
  echo ""
  term_footer "$TERM_NEUTRAL"
  printf '\n'
  return 0
}

term_pairs_row() { # <marker> <left> <right>
  _tpr_m=$1
  _tpr_l=$(term_truncate "$2" "$_tp_left")
  _tpr_r=$(term_truncate "$3" "$_tp_right")

  case "$_tpr_m" in
  ' '*)
    # A header keeps the two columns a marker and its space would
    # have taken, so its text lands where the rows' text lands.
    printf '%s%s  %s' "$TERM_INDENT" '' "$_tpr_l"
    term_columns_spaces $((_tp_left - ${#_tpr_l} + _tp_gap))
    printf '%s%s\n' "$_tpr_r" "$TERM_RESET"
    term_pairs_headrule
    return 0
    ;;
  esac
  printf '%s%s %s' "$TERM_INDENT" "$_tpr_m" "$_tpr_l"
  term_columns_spaces $((_tp_left - ${#_tpr_l} + _tp_gap))
  printf '%s%s\n' "$_tpr_r" "$TERM_RESET"
  return 0
}

# A rule is furniture: no glyph, and the frame's whole width.  It spans both
# columns because it is dividing the rows and not either column's contents --
# the same reason term_status gives one the frame's width rather than the text
# column's.
term_pairs_rule() { # <text>
  printf '%s%s%s%s\n' "$TERM_INDENT" "$TERM_NEUTRAL" \
    "$(term_truncate "$1" $((TERM_WIDTH - 2 - ${#TERM_INDENT})))" \
    "$TERM_RESET"
  return 0
}

# The rule under a header, which is not the caller's to pass and the same reason
# a table's header is not: the dashes have to be exactly as wide as the columns
# they sit under, and the widths are computed here rather than given.  A caller
# passing one would have to recompute _tp_left, _tp_right and _tp_gap to get the
# same numbers, and a rule one character short of its column reads as a
# mistake rather than as a divider.
#
# Drawn as one run under each column with the gap left open, not as a single
# unbroken line, and that is directory-pdf's columns_rule rather than a second
# opinion: a solid rule says "the rows are over", which under a header is not
# what has happened -- the rows are about to start.  What has happened is that
# the two names have been named, and the two runs say which column each name
# belongs to, which is the whole job of a header in a box with no gridlines.
term_pairs_headrule() {
  printf '%s%s  %s' "$TERM_INDENT" "$TERM_NEUTRAL" \
    "$(term_rep "$TERM_FRAME_HORIZONTAL" "$_tp_left")"
  term_columns_spaces "$_tp_gap"
  printf '%s%s%s\n' "$(term_rep "$TERM_FRAME_HORIZONTAL" "$_tp_right")" '' "$TERM_RESET"
  return 0
}

# ------------------------------------------------------------------ trouble
#
# A warning and an error are the same shape and different colours, which is the
# whole of the difference between them.  Both are one row of body text behind a
# marker, and both keep the frame in their own colour, because now the frame is
# the news: there is no orange-that-means-the-tool-speaking any more, so a red
# frame says error and an orange one says warning and a reader who is skimming
# gets the right one.
#
# These two are the one place the 62-column budget does not apply.  The advice
# in a failure -- the command to run to get unstuck -- is the entire point of
# the box, and cutting it to fit the frame would leave a message that looks
# complete and is not.  A long line overhangs the frame instead.
term_alert() { # $1 frame colour $2 marker $3 TITLE, then one or more messages
  _tal_c="$1"
  _tal_m="$2"
  _tal_title=$(printf '%s' "$3" | tr 'a-z' 'A-Z')
  shift 3
  printf '\n' >&2
  term_header "$_tal_c" "$_tal_title" "" >&2
  echo "" >&2
  # One argument is one warning; two are two warnings in one frame, and each
  # gets its own marker. They are framed together because they are about the
  # same run, and marked separately because they are not the same fact -- and
  # a second warning whose marker was missing because it was the second row of
  # the first one read as a footnote to it.
  #
  # Additive, and byte for byte the same output for the single-argument case
  # every caller in this repository already used, which is the only reason it
  # could be done without rewriting a golden file per tool. Within one
  # argument the rows after the first are still that warning's continuation,
  # which is what a hand-formatted block of advice needs.
  for _tal_msg in "$@"; do
    _tal_cols=$(term_marker_cols "$_tal_m")
    _tal_pad=$((_tal_cols + 1))
    _tal_firstpfx="$TERM_INDENT$_tal_c$_tal_m "
    _tal_contpfx="$TERM_INDENT$_tal_c$(term_rep ' ' "$_tal_pad")"
    printf '%s\n' "$_tal_msg" | (
      _tal_started=0
      while IFS= read -r _tal_line || [ -n "$_tal_line" ]; do
        if [ -z "$_tal_line" ]; then
          printf '\n'
          continue
        fi
        if [ "$_tal_started" -eq 0 ]; then
          term_wrap "$_tal_line" "$TERM_ROW" "$_tal_firstpfx" "$_tal_contpfx"
          _tal_started=1
        else
          term_wrap "$_tal_line" "$TERM_ROW" "$_tal_contpfx" "$_tal_contpfx"
        fi
      done
    )
  done >&2
  echo "" >&2
  term_footer "$_tal_c" >&2
  printf '\n' >&2
  return 0
}

# "$@" and not "$1": one argument is one warning, and more than one is more than
# one warning in a single frame, each with its own marker. See term_alert.
term_warn() { term_alert "$TERM_WARN" "$TERM_MARK_WARN" 'warning' "$@"; }
term_error() { term_alert "$TERM_ERROR" "$TERM_MARK_ERROR" 'error' "$@"; }

term_init
