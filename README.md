# nagios-plugins-vshn-icinga2

Currently the checks are written in Ruby and are proof-of-concept quality at best. Input validation and exception handling is very basic or not existing. Use at own risk!

The idea is to rewrite the scripts in Python or Go and using a Icinga2 API library.

## `late_check_results`
### Examples
```
apply Service "late_check_results_per_host" to Host {
  import "generic-service"
  display_name = "icinga2 late check results"
  assign where !host.vars.ignore_service_icinga
  check_command = "late_check_results"
  check_interval = 1h
  max_check_attempts = 1
  retry_interval = 5m
  enable_notifications = true
  zone = "master"
}
```
## `testalert`
```
apply Service "testalert" {
  import "generic-service"
  display_name = "Test Notification"
  check_command = "testalert"
  check_interval = 1m
  max_check_attempts = 1
  enable_notifications = true
  assign where host.vars.testalert

  vars.hour = "15"
  vars.weekday = "Thursday"
  vars.interval = 60
}
```

## `icinga2internals`

Checks some Icinga2 internal metrics for IDO, InfluxdbWriter, number of API endpoints, etc. As the check just uses the API, it can also check remote icinga2 instances.

High queues for IDO or InfluxDB usually indicate that the InfluxDB or the MariaDB server is not able to catchup with the load or the connection is broken otherwise. High queues can lead to icinga2 behaving strangely over time and data might get lost.
```
Usage: ./icinga2internals.rb [options]
    -H, --host=host
    -P, --port=port
    -u, --user=username
    -p, --password=password
    -w, --idowarn=value # default: 500
    -c, --idocrit=value # default: 1000
    -g, --influxwarn=value # default: 500
    -s, --influxcrit=value # default: 1000
```
### Example
```
./icinga2internals.rb -H <icingahost> -u <user> -p <key>
```
Output examples:
```
OK: ido_query_queue_items OK: 0, ido_query_queue_item_rate OK: 630, influx_data_buffer_items OK: 0, influx_work_queue_item_rate OK: 318, influx_work_queue_items OK: 19, num_not_conn_endpoints OK: 0
```
```
CRITICAL: influx_data_buffer_items NOT OK: 1014 greater 1000
```

## `submit_remote`

Can be use with any Icinga2 / Nagios check script to submit the result as a passive check result to any Icinga2 instance via the API. A API user with sufficient permissions is needed.

It basically runs the command specified by `-c` and submits the results so the host and service specified by `-s`.

```
Usage: ./submit_remote.rb [options]
    -H, --host=MANDATORY
    -P, --port=MANDATORY
    -u, --user=MANDATORY
    -p, --password=MANDATORY
    -c, --command=MANDATORY
    -s, --remoteservice=MANDATORY # example: hostname!servicename
```

### Examples
This one checks the icinga2 internals (see above) and forwards the results to a remote icinga2. The check also passes through the results to the local Icinga2, so it's basically transparent.
```
./submit_remote.rb -H <remote icinga host> -s 'icinga-server.vagrant.dev!icinga2_test.remote.vagrant.dev' -u <remote user> -p <remote pass> -c "./icinga2internals.rb -H localhost -u <local user> -p <local pass>"
```

## Example Icinga2 config
service on the remote icinga2 with "heartbeat" / freshness check:
```
object Service "icinga2_test.remote.vagrant.dev" {
  check_command = "dummy"
  check_interval = 10s

  /* Set the state to UNKNOWN (3) if freshness checks fail. */
  vars.dummy_state = 2

  /* Use a runtime function to retrieve the last check time and more details. */
  vars.dummy_text = {{
    var service = get_service(macro("$host.name$"), macro("$service.name$"))
    var lastCheck = DateTime(service.last_check).to_string()

    return "No check results received. Last result time: " + lastCheck
  }}

  host_name = "icinga-server.vagrant.dev"
}
```
local check:
```
object Service "icinga2internals" {
  check_command = "submit_remote"
  check_interval = 20s
  display_name = "Icinga2 internal metrics"

  vars.submit_remote_host = "localhost"
  vars.submit_remote_user = "user"
  vars.submit_remote_password = "pass"
  vars.submit_remote_remoteservice = "icinga-server.vagrant.dev!icinga2_test.remote.vagrant.dev"
  vars.submit_remote_command = PluginDir + "/icinga2internals.rb -H localhost -u <local user> -p <local pass>

  host_name = "icinga-server.vagrant.dev"
}
```
