# MondayReport

MondayReport is a script for generating a weekly report for a webserver based on system statistics and logs. 

The goal is to generate a mobile-friendly email that a lazy sysadmin could read out of the corner of their eye while waiting in line at their favourite coffee joint, red-eyed and hungover on a rainy Monday morning...

This script is designed to run on Ubuntu 18.04 servers, but could be adapted for other distributions with a small amount of work. 

### Examples

See an example: [report.html](/examples/report.html)

## Requirements

### sysstat 

Metrics are compiled using the daily logs generated by `systtat`. 

First, install the package: 

    sudo apt install -y systtat 

Then, edit the config file: 

**`/etc/default/sysstat`**
```ini
...
ENABLED="true"
```

Finally, restart the service. 

    sudo systemctl restart sysstat 

### Pandoc

Pandoc is used for converting the generated markdown file into HTML for email. 

The version shipped with Ubuntu 18.04 is sufficient, and can be installed from the repository. 

    sudo apt install -y pandoc

### Mail Relay

Make sure a MTA service is set up on the server to allow mail sent to `root` to be forwarded to an outside mailbox. There are many ways to do this, the standard being Postfix on localhost. 

Then, ensure that aliases are set up correctly at `/etc/aliases`

```
postmaster:    root
root:          webmaster@gablogianartcollective.org
```

If modified, be sure to run `sudo newaliases`. 

### Suricata (optional)

If suricata is installed, make sure logrotate is enabled with this configuration: 

```
/var/log/suricata/*.log /var/log/suricata/*.json
{
    rotate 14
    missingok
    ifempty
    nocompress
    create
    sharedscripts
    postrotate
            /bin/kill -HUP $(cat /var/run/suricata.pid)
    endscript
}
```

## Installation

To create the weekly report, the script must be placed in an appropriate directory, such as `/opt/scripts` with mode `0640`. 

Then, the cron entry can be created. 

**`/etc/cron.d/mondayreport`**

```
MAILTO=root
00 08 * * 1     root    /opt/scripts/mondayreport/report.sh
```

Note that this time is 8:00 AM UTC, which may not be correct for your timezone. 