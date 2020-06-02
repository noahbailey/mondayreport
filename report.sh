#!/bin/bash 

# Weekly report script
#   Give a brief status update to a sysadmin based on some readily available data
#   This script will run on Monday at 08:00 UTC

MD="/tmp/report.md"

# Add inline CSS to print tables correctly: 
echo "<style type="text/css">table {border-collapse: collapse;} table, th, td { border: 1px solid black; padding: 2px }</style>" > $MD

# Document header: 
echo "## $HOSTNAME 🤖 Weekly Report" >> $MD
echo "" >> $MD

# System Facts
# ------------
echo "### System Facts" >> $MD 
source /etc/lsb-release
MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{$2=$2/1024; print $2,"MB";}')
NUM_CPUS=$(grep -c ^processor /proc/cpuinfo)

echo "Operating System | Kernel | Memory | CPUs" >> $MD
echo "------ | ------ | ------ | ----" >> $MD
echo "$DISTRIB_DESCRIPTION | $(uname -r ) | $MEM_TOTAL | $NUM_CPUS " >> $MD

# Add a blank line before the next section 
echo "" >> $MD

# System Status
# -------------
if [ -e /var/run/reboot-required ]; then 
    echo ":recycle: Needs reboot (System $(uptime -p)" >> $MD
    echo "" >> $MD
fi 

# Available updates: 
echo ":arrow_up: Updates are available:" >> $MD
echo >> $MD
echo '```' >> $MD
/usr/lib/update-notifier/apt-check --human-readable  >> $MD
echo '```' >> $MD

# Add a blank line before the next section 
echo "" >> $MD


# High CPU
# --------

echo "High CPU Periods:" >> $MD

for days_ago in {0..7}; do 
    unset spike_time 
    spike_time=$(sar -$days_ago | awk '$8 ~ /^[1-9].[0-9]{2}/ {print $1}')
    if [ -n "$spike_time" ]; then 
        echo "* $(date -d "-$days_ago day" +%m/%d) $spike_time " >> $MD
    fi 
done 


# Get current disk usage
# ----------------------
echo "### Disk Usage" >> $MD
echo '```' >> $MD
df -hl | grep -Ev "tmpfs|udev|snap" >> $MD
echo '```' >> $MD


# Read 7 days of sysstat entries
echo "" >> $MD
echo "### Performance Metrics" >> $MD
echo "" >> $MD

echo "DAY | CPU Avg | Load Avg | Mem Avg " >> $MD
echo "--- | ------- | -------- | ------- " >> $MD
for days_ago in {1..7}; do 
    # Only report system metrics if they exist in sysstat. 
    if [ -e /var/log/sysstat/sa$(date -d "-$days_ago day" +%d) ]; then 
        cpu_avg=$(sar -$days_ago | grep Average | awk '{print $3}') 
        load_avg=$(sar -$days_ago -q | grep Average | awk '{print $5}')
        mem_avg=$(sar -$days_ago -r | grep Average | awk '{print $5}')
        echo "$(date -d "-$days_ago day" +%a) | $cpu_avg | $load_avg | $mem_avg" >> $MD
    fi 
done

# Add a blank line before the next section 
echo "" >> $MD

# Read 7 days of System logs    
# --------------------------
echo "### System Logs" >> $MD

# Find messages with these strings:
ERR_REGEX="ERROR|SEVERE|WARN"
EXCLUDE="systemd-resolved"

echo "Errors per Service / Day " >> $MD 

for days_ago in {1..7}; do 
    if [ -e /var/log/syslog.$days_ago ]; then 
        case $days_ago in 
            1) cmd="grep"  ;;
            *) cmd="zgrep" ;; 
        esac 

        echo "$(date -d "-$days_ago day" +%a): " >> $MD

        # Calculate the number of log entries 
        logs=$($cmd -iE $ERR_REGEX /var/log/syslog.$days_ago | grep -v "$EXCLUDE" | \
            awk '{print $5}' |  sed 's/://' | sort | uniq -c | sed "s/^\s*//g" | sed "s/^/* /" )

        # Add the types of errors that occurred 
        echo "$logs " >> $MD
    fi 
done 

# Add a blank line before the next section 
echo "" >> $MD


# Read 7 days of Nginx logs
# -------------------------
echo "### Nginx Logs" >> $MD

# Logrotate on Ubuntu is configured to leave 1 day uncompressed, then gzip the rest of the logs. 
#   So, the 'sunday' logs have to be handled differently. 
REGEX_200="HTTP/(1|2)\.(1|0)\" 2[0-9]{2}"
REGEX_300="HTTP/(1|2)\.(1|0)\" 3[0-9]{2}"
REGEX_400="HTTP/(1|2)\.(1|0)\" 4[0-9]{2}"
REGEX_500="HTTP/(1|2)\.(1|0)\" 5[0-9]{2}"

echo "Day | 2xx | 3xx | 4xx | 5xx" >> $MD
echo "--- | --- | --- | --- | ---" >> $MD

for days_ago in {1..7}; do 
    if [ -e /var/log/nginx/access.log.$days_ago ]; then 
        case $days_ago in 
            1) cmd="grep"  ;;
            *) cmd="zgrep" ;; 
        esac 

        # The file path does not determine the type
        file="/var/log/nginx/access.log.$days_ago"
        
        # Parse the logs using the grep/zgrep command: 
        LOGS_200=$($cmd -E "$REGEX_200" $file | wc -l )
        LOGS_300=$($cmd -E "$REGEX_300" $file | wc -l )
        LOGS_400=$($cmd -E "$REGEX_400" $file | wc -l )
        LOGS_500=$($cmd -E "$REGEX_500" $file | wc -l )

        echo "$(date -d "-$days_ago day" +%a) |  $LOGS_200 | $LOGS_300 | $LOGS_400 | $LOGS_500 " >> $MD
    fi 
done; 

# Add a blank line before the next section 
echo "" >> $MD

# Read 7 days of Suricata logs
# ----------------------------

echo "### Suricata Alerts" >> $MD

echo "Day | Low | Med | High " >> $MD
echo "--- | --- | --- | ---- " >> $MD

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


# ==> Export to HTML
pandoc --from=markdown_github --to=html /tmp/report.md -o /tmp/report.html --standalone

#cat /tmp/report.html | mail -s "$HOSTNAME - Weekly Report" -a 'Content-Type: text/html' root 
