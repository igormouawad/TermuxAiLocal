#!/usr/bin/env bash

desktop::resolve_component() {
  local device_id="$1"
  local package_name="$2"
  local resolved_component

  resolved_component="$(
    adb -s "$device_id" shell cmd package resolve-activity --brief "$package_name" 2>/dev/null \
      | tr -d '\r' \
      | awk 'NF { line = $0 } END { print line }'
  )"

  if [ -z "$resolved_component" ] || ! printf '%s\n' "$resolved_component" | grep -Fq '/'; then
    return 1
  fi

  printf '%s\n' "$resolved_component"
}

desktop::dump() {
  local device_id="$1"

  adb -s "$device_id" shell wm shell desktopmode dump 2>/dev/null | tr -d '\r'
}

desktop::active_desk_id() {
  local device_id="$1"
  local dump_output
  local desk_id

  dump_output="$(desktop::dump "$device_id")"
  desk_id="$(
    printf '%s\n' "$dump_output" \
      | sed -nE 's/^[[:space:]]*activeDesk=([0-9]+).*/\1/p' \
      | head -n1
  )"

  if [ -n "$desk_id" ]; then
    printf '%s\n' "$desk_id"
    return 0
  fi

  if ! printf '%s\n' "$dump_output" | grep -Fq 'inDesktopWindowing=true'; then
    return 1
  fi

  desk_id="$(
    printf '%s\n' "$dump_output" \
      | sed -nE 's/^[[:space:]]*Desk #([0-9]+):.*/\1/p' \
      | head -n1
  )"

  [ -n "$desk_id" ] || return 1
  printf '%s\n' "$desk_id"
}

desktop::task_id_by_package() {
  local device_id="$1"
  local package_name="$2"

  adb -s "$device_id" shell cmd activity stack list 2>/dev/null | awk -v package_name="$package_name" '
    $0 ~ ("taskId=[0-9]+: " package_name "/") && $0 ~ /visible=true/ {
      line = $0
      sub(/^.*taskId=/, "", line)
      sub(/:.*/, "", line)
      print line
      exit
    }

    $0 ~ ("taskId=[0-9]+: " package_name "/") && fallback == "" {
      fallback = $0
    }

    END {
      if (fallback != "") {
        line = fallback
        sub(/^.*taskId=/, "", line)
        sub(/:.*/, "", line)
        print line
      }
    }
  '
}

desktop::visible_task_table() {
  local device_id="$1"

  adb -s "$device_id" shell cmd activity stack list 2>/dev/null | awk '
    $0 ~ /taskId=[0-9]+:/ && $0 ~ /visible=true/ {
      line = $0
      if (match(line, /taskId=[0-9]+/)) {
        task = substr(line, RSTART + 7, RLENGTH - 7)
      } else {
        next
      }

      split(line, pieces, ": ")
      if (length(pieces) < 2) {
        next
      }

      split(pieces[2], activity_part, "/")
      package_name = activity_part[1]
      if (package_name == "") {
        next
      }

      print task "\t" package_name "\t" line
    }
  '
}

desktop::task_windowing_mode() {
  local device_id="$1"
  local task_id="$2"

  adb -s "$device_id" shell cmd activity stack list 2>/dev/null | awk -v task_id="$task_id" '
    /^RootTask id=/ {
      current_mode = ""
      next
    }

    /mWindowingMode=/ {
      if (match($0, /mWindowingMode=[^ ]+/)) {
        current_mode = substr($0, RSTART + length("mWindowingMode="), RLENGTH - length("mWindowingMode="))
      }
      next
    }

    $0 ~ ("taskId=" task_id ":") {
      if (current_mode != "") {
        print current_mode
        exit
      }
    }
  '
}

desktop::wait_for_task_windowing_mode() {
  local device_id="$1"
  local task_id="$2"
  local expected_mode="$3"
  local timeout_seconds="${4:-10}"
  local deadline_seconds
  local current_mode

  deadline_seconds=$(( $(date +%s) + timeout_seconds ))

  while :; do
    current_mode="$(desktop::task_windowing_mode "$device_id" "$task_id" || true)"
    if [ "$current_mode" = "$expected_mode" ]; then
      return 0
    fi

    if [ "$(date +%s)" -ge "$deadline_seconds" ]; then
      break
    fi

    sleep 0.3
  done

  return 1
}

desktop::move_task_to_desk() {
  local device_id="$1"
  local task_id="$2"
  local desk_id="$3"

  if [ "$(desktop::task_windowing_mode "$device_id" "$task_id" || true)" = 'freeform' ]; then
    return 0
  fi

  adb -s "$device_id" shell wm shell desktopmode moveTaskToDesk "$task_id" "$desk_id" >/dev/null 2>&1 || true
  desktop::wait_for_task_windowing_mode "$device_id" "$task_id" freeform 10
}

desktop::resize_task() {
  local device_id="$1"
  local task_id="$2"
  local bounds_text="$3"
  local left
  local top
  local right
  local bottom

  read -r left top right bottom <<<"$bounds_text"

  adb -s "$device_id" shell cmd activity task resizeable "$task_id" 3 >/dev/null 2>&1 || true
  adb -s "$device_id" shell cmd activity task resize "$task_id" "$left" "$top" "$right" "$bottom" >/dev/null 2>&1
}

desktop::focus_task() {
  local device_id="$1"
  local display_id="$2"
  local task_id="$3"
  local component_name="${4:-}"

  adb -s "$device_id" shell wm shell desktopmode moveTaskToFront "$task_id" >/dev/null 2>&1 || true
  sleep 0.5

  if [ -n "$component_name" ]; then
    adb -s "$device_id" shell cmd activity start-activity \
      --display "$display_id" \
      --activity-reorder-to-front \
      -n "$component_name" \
      >/dev/null 2>&1 || true
    sleep 0.5
  fi
}

desktop::start_freeform_activity() {
  local device_id="$1"
  local display_id="$2"
  local windowing_mode="$3"
  local component_name="$4"

  adb -s "$device_id" shell cmd activity start-activity \
    --display "$display_id" \
    --windowingMode "$windowing_mode" \
    -W \
    -n "$component_name" \
    >/dev/null 2>&1
}

desktop::display_bounds() {
  local device_id="$1"
  local bounds_text
  local width_height
  local width
  local height

  bounds_text="$(
    adb -s "$device_id" shell cmd activity stack list 2>/dev/null \
      | awk '
          /^RootTask id=/ && match($0, /bounds=\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]/) {
            bounds = substr($0, RSTART, RLENGTH)
            parsed = bounds
            gsub(/bounds=\[/, "", parsed)
            gsub(/\]\[/, " ", parsed)
            gsub(/\]/, "", parsed)
            gsub(/,/, " ", parsed)
            split(parsed, parts, /[[:space:]]+/)
            if (parts[1] != "" && parts[4] != "") {
              width = parts[3] - parts[1]
              height = parts[4] - parts[2]
              area = width * height
              if (width >= height) {
                if (area > best_landscape_area) {
                  best_landscape_area = area
                  best_landscape_bounds = bounds
                }
              } else {
                if (area > best_area) {
                  best_area = area
                  best_bounds = bounds
                }
              }
            }
          }

          END {
            if (best_landscape_bounds != "") {
              print best_landscape_bounds
            } else if (best_bounds != "") {
              print best_bounds
            }
          }
        '
  )"

  if [ -n "$bounds_text" ]; then
    printf '%s\n' "$bounds_text" | sed -E 's/.*\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\].*/\1 \2 \3 \4/'
    return 0
  fi

  width_height="$(
    adb -s "$device_id" shell wm size 2>/dev/null \
      | tr -d '\r' \
      | awk -F': ' '/Physical size:/ { print $2; exit }'
  )"

  if [ -z "$width_height" ] || ! printf '%s\n' "$width_height" | grep -Eq '^[0-9]+x[0-9]+$'; then
    return 1
  fi

  width="${width_height%x*}"
  height="${width_height#*x}"
  if [ "$height" -gt "$width" ]; then
    printf '0 0 %s %s\n' "$height" "$width"
  else
    printf '0 0 %s %s\n' "$width" "$height"
  fi
}

desktop::system_bar_insets() {
  local device_id="$1"
  local windows_output
  local top_inset
  local bottom_inset

  windows_output="$(adb -s "$device_id" shell dumpsys window windows 2>/dev/null | tr -d '\r')"

  top_inset="$(
    printf '%s\n' "$windows_output" \
      | sed -n '/Window #.*StatusBar/,/Window #/p' \
      | sed -nE 's/.*Insets\{left=[0-9]+, top=([0-9]+), right=[0-9]+, bottom=[0-9]+\}.*/\1/p' \
      | head -n1
  )"

  bottom_inset="$(
    printf '%s\n' "$windows_output" \
      | sed -n '/Window #.*TaskbarWindow/,/Window #/p' \
      | sed -nE 's/.*Insets\{left=[0-9]+, top=[0-9]+, right=[0-9]+, bottom=([0-9]+)\}.*/\1/p' \
      | head -n1
  )"

  printf '0 %s 0 %s\n' "${top_inset:-0}" "${bottom_inset:-0}"
}

desktop::usable_bounds() {
  local device_id="$1"
  local display_left
  local display_top
  local display_right
  local display_bottom
  local inset_left
  local inset_top
  local inset_right
  local inset_bottom

  read -r display_left display_top display_right display_bottom <<<"$(desktop::display_bounds "$device_id")"
  read -r inset_left inset_top inset_right inset_bottom <<<"$(desktop::system_bar_insets "$device_id")"

  printf '%s %s %s %s\n' \
    "$((display_left + inset_left))" \
    "$((display_top + inset_top))" \
    "$((display_right - inset_right))" \
    "$((display_bottom - inset_bottom))"
}

desktop::scale_bounds() {
  local base_bounds="$1"
  local base_display_width="$2"
  local base_display_height="$3"
  local display_left="$4"
  local display_top="$5"
  local display_width="$6"
  local display_height="$7"
  local base_left
  local base_top
  local base_right
  local base_bottom
  local scaled_left
  local scaled_top
  local scaled_right
  local scaled_bottom

  read -r base_left base_top base_right base_bottom <<<"$base_bounds"

  scaled_left=$((display_left + (base_left * display_width / base_display_width)))
  scaled_top=$((display_top + (base_top * display_height / base_display_height)))
  scaled_right=$((display_left + (base_right * display_width / base_display_width)))
  scaled_bottom=$((display_top + (base_bottom * display_height / base_display_height)))

  printf '%s %s %s %s\n' "$scaled_left" "$scaled_top" "$scaled_right" "$scaled_bottom"
}
