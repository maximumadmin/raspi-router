
function get_fs_mode() {
  local RE="^$(echo "${1}" | sed 's/\//\\\//g')\$"
  awk -v re=$RE \
  '$2~re {mode=substr($4,1,2); if($1 == "overlay"){mode=mode"*"}; print mode}' \
  /proc/mounts
}

export PS1="\[\e[32m\]\u\[\e[m\]\[\e[32m\]@\[\e[m\]\[\e[32m\]\h\[\e[m\] \[\e[36m\]\w\[\e[m\] \[\e[33m\](boot: \`get_fs_mode /boot\` root: \`get_fs_mode /\` data: \`get_fs_mode {STORAGE_PATH}\`)\[\e[m\]\n\\$ "
