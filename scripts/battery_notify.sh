#!/bin/bash
LOCKFILE=/tmp/battery_notify.lock

exec 200>"$LOCKFILE"
flock -n 200 || { echo "Another instance is running. Exiting."; exit 1; }

CRITICAL_BATTERY_THRESHOLD=10
LOW_BATTERY_THRESHOLD=30
STATE_FLAG="/run/user/$UID/sling_battery_state"
NOTIFICATION_FLAG="/run/user/$UID/sling_battery_notified"
LAST_NOTIFICATION_ID_FILE="/run/user/$UID/sling_battery_last_notification_id"

get_battery_percentage() {
  upower -i "$(upower -e | grep 'BAT')" \
  | awk -F: '/percentage/ {
      gsub(/[%[:space:]]/, "", $2);
      val=$2;
      printf("%d\n", (val+0.5))
      exit
    }'
}

get_battery_state() {
  upower -i "$(upower -e | grep 'BAT')" | awk -F: '/state/ {gsub(/[[:space:]]/, "", $2); print $2}'
}


LAST_NOTIFICATION_ID_FILE="/tmp/last_notify_id"
send_notify() {
    # Read last notification ID, default to 0
    local last_id
    last_id=$(cat "$LAST_NOTIFICATION_ID_FILE" 2>/dev/null || echo "0")

    # Send the notification, replacing the previous one, and capture the new ID
    local new_id
    new_id=$(notify-send "$@" --replace-id="$last_id" --print-id)

    # Store the new notification ID for next time
    echo "$new_id" > "$LAST_NOTIFICATION_ID_FILE"
}

play_sound() {
    paplay "$@"
}


send_critical_notification() {
  send_notify -u critical "󱐋 Time to recharge!" "Battery is down to ${1}%" -i battery-caution -t 30000
  paplay /usr/share/sounds/freedesktop/stereo/suspend-error.oga
}

send_low_notification() {
  send_notify -u normal "󱐊 Low Battery" "Battery is at ${1}%" -i battery-low -t 15000
  paplay /usr/share/sounds/freedesktop/stereo/message-new-instant.oga
}

send_charging_notification() {
  send_notify -u low "⚡ Charging" "Your system is now charging." -i battery-good -t 2000
  play_sound /usr/share/sounds/freedesktop/stereo/complete.oga
}

send_discharging_notification() {
  send_notify -u normal "🔋 On Battery Power" "Your system is now running on battery." -i battery -t 10000
  play_sound /usr/share/sounds/freedesktop/stereo/dialog-error.oga
}

send_fullycharged_notification() {
  send_notify -u low "🔌 Fully Charged" "Your battery is fully charged." -i battery-full -t 5000
  play_sound /usr/share/sounds/freedesktop/stereo/complete.oga
}

BATTERY_LEVEL=$(get_battery_percentage)
BATTERY_STATE=$(get_battery_state)

# Detect state change (charging/discharging)
if [[ -f "$STATE_FLAG" ]]; then
  LAST_STATE=$(cat "$STATE_FLAG")
else
  LAST_STATE=""
fi

if [[ "$BATTERY_STATE" != "$LAST_STATE" ]]; then
  # Clear previous state notifications
  rm -f "$NOTIFICATION_FLAG.state"

  if [[ "$BATTERY_STATE" == "charging" ]]; then
    send_charging_notification
    touch "$NOTIFICATION_FLAG.state.charging"
  elif [[ "$BATTERY_STATE" == "discharging" ]]; then
    send_discharging_notification
    touch "$NOTIFICATION_FLAG.state.discharging"
  elif [[ "$BATTERY_STATE" == "fully-charged" ]]; then
    send_fullycharged_notification
    touch "$NOTIFICATION_FLAG.state.fully_charged"
  fi

  echo "$BATTERY_STATE" > "$STATE_FLAG"
fi

# Battery-level notifications
if [[ "$BATTERY_STATE" == "discharging" ]]; then
  if [[ "$BATTERY_LEVEL" -le "$CRITICAL_BATTERY_THRESHOLD" ]]; then
    if [[ ! -f "$NOTIFICATION_FLAG.critical" ]]; then
      send_critical_notification "$BATTERY_LEVEL"
      touch "$NOTIFICATION_FLAG.critical"
    fi
  elif [[ "$BATTERY_LEVEL" -le "$LOW_BATTERY_THRESHOLD" ]]; then
    if [[ ! -f "$NOTIFICATION_FLAG.low" ]]; then
      send_low_notification "$BATTERY_LEVEL"
      touch "$NOTIFICATION_FLAG.low"
    fi
  else
    rm -f "$NOTIFICATION_FLAG.low" "$NOTIFICATION_FLAG.critical"
  fi
else
  rm -f "$NOTIFICATION_FLAG.low" "$NOTIFICATION_FLAG.critical"
fi

