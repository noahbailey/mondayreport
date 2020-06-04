#!/bin/bash 

# Weekly report script
#   Give a brief status update to a sysadmin based on some readily available data
#   While there are many 'daily report' scripts, that can quickly cause fatigue. 
#   This script will run on Monday morning, just in time for the first coffee pot
#   This report aggregates the following data: 
#       * Syslogs 
#       * Sysstat metrics
#       * Nginx server logs
#       * Suricata network monitoring
#       * And more...
#
#   Then, the markdown file is rendered into a HTML email body and 
#     emailed to the system administrator. 
#   It can also be optionally exported as a PDF document 

MD="/tmp/report.md"

# Add inline CSS to print tables correctly: 
echo "<style type="text/css">table {border-collapse: collapse;} table, th, td { border: 1px solid black; padding: 2px }</style>" > $MD

# Document header: 
echo "## $HOSTNAME | Weekly System Report" >> $MD
echo "" >> $MD

# System Status
# -------------

# Indicate if services have failed... 
failed_services=$(systemctl --failed | grep 'failed' | awk '{print $2}')
if [ -n $failed_services ]; then 
    echo ":thumbsup: All services running. " >> $MD 
else 
    echo ":thumbsdown: Services failed:" >> $MD
    echo '```' >> $MD 
    echo "$failed_services" >> $MD 
    echo '```' >> $MD 
fi 

# Indicate if the system needs a reboot
if [ -e /var/run/reboot-required ]; then 
    echo ":recycle: Needs reboot." >> $MD
fi 

# Available updates: 
update_status="$(/usr/lib/update-notifier/apt-check 2>&1)"
if [ $update_status != "0;0" ]; then 
    echo ":arrow_up: Updates are available. " >> $MD
else
    echo ":heavy_check_mark: System is up to date. " >> $MD
fi 

# Add a blank line before the next section 
echo "" >> $MD


# System Facts
# ------------
echo "### System Facts" >> $MD 
source /etc/lsb-release
MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{$2=$2/1024; print $2,"MB";}')
NUM_CPUS=$(grep -c ^processor /proc/cpuinfo)
TIMEZONE=$(date +%Z)

# Print OS stats as table: 
echo "Operating System | $DISTRIB_DESCRIPTION " >> $MD 
echo "---------------- | -------------------- " >> $MD 
echo "Kernel           | $(uname -r )"          >> $MD 
echo "Timezone         | $TIMEZONE "            >> $MD
echo "Memory           | $MEM_TOTAL "           >> $MD 
echo "CPUs             | $NUM_CPUS "            >> $MD 

# Add a row to the table for each filesystem: 
df -Hl | grep -Ev "tmpfs|udev|snap|boot|Filesystem" | while read line; do 
    echo "$line" | awk '{print "Filesystem: " $6 " | " $3 " / "  $4 " (" $5 ")"}' >> $MD
done; 

# Add a blank line before the next section 
echo "" >> $MD

# Recent Logins
# -------------

echo "Recent logins: " >> $MD
echo "" >> $MD 
echo "Logins | Username | Source IP" >> $MD 
echo "------ | -------- | ---------" >> $MD 
last | grep -Ev "tmux|screen|begins" | awk '$1 != ""  {print " | " $1 " | " $3}' \
    | uniq -c | sort | sed -e 's/^[[:space:]]*//' >> $MD

# Add a blank line before the next section 
echo "" >> $MD


# Performance Metrics 
# --------------------

# Read 7 days of sysstat entries
echo "" >> $MD
echo "### :bar_chart: Performance Metrics :bar_chart:" >> $MD

echo -e "\nPer-Day averages this week:\n" >> $MD

echo "Day of Week | %CPU | Load | %Mem " >> $MD
echo "----------- | ---- | ---- | ---- " >> $MD
for days_ago in {1..7}; do 
    # Only report system metrics if they exist in sysstat. 
    if [ -e /var/log/sysstat/sa$(date -d "-$days_ago day" +%d) ]; then 
        # sar sometimes prints two averages if the system restarted.
        #   so, just accept the last average it took from that day. 
        cpu_avg=$(sar -$days_ago     | grep Average | tail -n1 | awk '{print $3}') 
        load_avg=$(sar -$days_ago -q | grep Average | tail -n1 | awk '{print $5}')
        mem_avg=$(sar -$days_ago  -r | grep Average | tail -n1 | awk '{print $5}')
        echo "$(date -d "-$days_ago day" +%a) | $cpu_avg | $load_avg | $mem_avg" >> $MD
    fi 
done

# Add a blank line before the next section 
echo "" >> $MD

# High CPU
# --------

echo "High CPU Periods:" >> $MD

for days_ago in {0..7}; do 
    unset spike_time 
    spike_time=$(sar -$days_ago | awk '$8 ~ /^[1-9].[0-9]{2}/ {print $1}')
    if [ -n "$spike_time" ]; then 
        echo "* $(date -d "-$days_ago day" +%y-%m-%d) $spike_time " >> $MD
    fi 
done 

# Add a blank line before the next section 
echo "" >> $MD



# Read 7 days of System logs    
# --------------------------
echo "### :scroll: System Logs :scroll:" >> $MD

# Find messages with these strings:
ERR_REGEX="ERROR|SEVERE|WARN"
EXCLUDE="systemd-resolved"

echo -e "\nErrors per Service/Process per Day. A high number of errors could indicate an issue with this system.\n" >> $MD 

for days_ago in {1..7}; do 
    case $days_ago in 
        1) cmd="grep"
           file="/var/log/syslog.1" ;;
        *) cmd="zgrep" 
           file="/var/log/syslog.$days_ago.gz" ;; 
    esac 

    # Calculate the number of log entries 
    logs=$($cmd  -iE $ERR_REGEX $file | grep -v "$EXCLUDE" | \
        awk '{gsub(/\[[0-9]+\]|:/,"");print $5}' | sort | uniq -c | sed "s/^\s*//g" | sed "s/^/* /" )

    # If there are logs, add them to the report
    [ -n "$logs" ] && echo -e "$(date -d "-$days_ago day" +%y-%m-%d): \n$logs \n" >> $MD
done 


# Read 7 days of Nginx logs
# -------------------------
echo "### :globe_with_meridians: Nginx Logs :globe_with_meridians:" >> $MD

# Logrotate on Ubuntu is configured to leave 1 day uncompressed, then gzip the rest of the logs. 
#   So, the 'sunday' logs have to be handled differently. 
REGEX_200="HTTP/(1|2)\.(1|0)\" 2[0-9]{2}"
REGEX_300="HTTP/(1|2)\.(1|0)\" 3[0-9]{2}"
REGEX_400="HTTP/(1|2)\.(1|0)\" 4[0-9]{2}"
REGEX_500="HTTP/(1|2)\.(1|0)\" 5[0-9]{2}"

echo "Day of Week | 2xx | 3xx | 4xx | 5xx" >> $MD
echo "----------- | --- | --- | --- | ---" >> $MD

for days_ago in {1..7}; do 

    case $days_ago in 
        1) cmd="grep"
            file="/var/log/nginx/access.log.$days_ago"  ;;
        *) cmd="zgrep" 
            file="/var/log/nginx/access.log.$days_ago.gz" ;; 
    esac 

    # Go to next loop if the log file does not exist
    if [ ! -f $file ]; then continue; fi 

    # Parse the logs using the grep/zgrep command: 
    LOGS_200=$($cmd -E "$REGEX_200" $file | wc -l )
    LOGS_300=$($cmd -E "$REGEX_300" $file | wc -l )
    LOGS_400=$($cmd -E "$REGEX_400" $file | wc -l )
    LOGS_500=$($cmd -E "$REGEX_500" $file | wc -l )

    echo "$(date -d "-$days_ago day" +%a) |  $LOGS_200 | $LOGS_300 | $LOGS_400 | $LOGS_500 " >> $MD

done; 

# Add a blank line before the next section 
echo "" >> $MD

# Read 7 days of Suricata logs
# ----------------------------

echo "### :mag: Suricata Alerts :mag:" >> $MD

echo "Day of Week | Low | Med | High " >> $MD
echo "----------- | --- | --- | ---- " >> $MD

for days_ago in {1..7}; do 
    if [ -e /var/log/suricata/fast.log.$days_ago ]; then 
        case $days_ago in 
            1) cmd="grep"  ;;
            *) cmd="zgrep" ;; 
        esac 

        # The file path does not determine the type
        file="/var/log/suricata/fast.log.$days_ago"
        
        # Parse the logs using the grep/zgrep command: 
        LOGS_LOW=$($cmd -E "Priority: 3" $file | wc -l )
        LOGS_MED=$($cmd -E "Priority: 2" $file | wc -l )
        LOGS_HI=$($cmd -E  "Priority: 1" $file | wc -l )

        echo "$(date -d "-$days_ago day" +%a) |  $LOGS_LOW | $LOGS_MED | $LOGS_HI " >> $MD
    fi 
done; 


# ==> Export to HTML and send e-mail to 'Root'
pandoc --from=markdown_github --to=html /tmp/report.md -o /tmp/report.html --self-contained
mailx -s "$HOSTNAME | Weekly System Report" -a 'Content-Type: text/html' root < /tmp/report.html
