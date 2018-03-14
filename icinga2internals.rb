#!/usr/bin/ruby

require 'net/http'
require 'uri'
require 'json'
require 'optparse'

options = {}
results = {}
states = { 0 => 'OK', 1 => 'WARNING', 2 => 'CRITICAL', 3 => 'UNKNOWN' }
options[:port] = 5665
options[:ido_warn] = 500
options[:ido_crit] = 1000
options[:influx_warn] = 500;
options[:influx_crit] = 1000;

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"
  opts.on("-H", "--host=host" , String) do |host|
    options[:host] = host;
  end
  opts.on("-P", "--port=port", Integer) do |v|
    options[:port] = v;
  end
  opts.on("-u", "--user=username", String) do |v|
    options[:user] = v;
  end
  opts.on("-p", "--password=password", String) do |v|
    options[:pass] = v;
  end
  opts.on("-w", "--idowarn=value", Integer) do |v|
    options[:ido_warn] = v;
  end
  opts.on("-c", "--idocrit=value", Integer) do |v|
    options[:ido_crit] = v;
  end
  opts.on("-g", "--influxwarn=value", Integer) do |v|
    options[:influx_warn] = v;
  end
  opts.on("-s", "--influxcrit=value", Integer) do |v|
    options[:influx_crit] = v;
  end
end.parse!
raise ArgumentError.new("Wrong number of options") unless options.keys.count == 8

def get_status_values(status_object, name, key)
  # only get the first instance, multiple instnaces of ido / influx, etc. not supported atm
  if a = status_object['results'].select {|key| key['name'] == name}[0]
    return a['status'][key].first[1]
  end
end

def compare_metric(current, warn, crit, name)
  if current.round > crit
    return { :code => 2, :text => name + ' NOT OK: ' + current.round.to_s + ' > ' + crit.to_s }
  elsif current.round > warn
    return { :code => 1, :text => name + ' NOT OK: ' + current.round.to_s + ' > ' + warn.to_s }
  end
  return { :code => 0, :text => name + ' OK: ' + current.round.to_s }
end

header = {
  "Accept" => "application/json",
  "X-HTTP-Method-Override" => "GET"
}
begin
  # Create the HTTP objects
  http = Net::HTTP.start(options[:host], options[:port], :use_ssl => true, :verify_mode => 0)
  request = Net::HTTP::Get.new('/v1/status', header)
  request.basic_auth options[:user], options[:pass]
  response = http.request(request)
  if response.code != '200'
    puts 'UNKNOWN: API call to ' + options[:host] + ' failed: ' + response.code + ' ' + response.message
    exit 3
  end
  status_object = JSON.parse(response.body)

  if influx_status = get_status_values(status_object, 'InfluxdbWriter', 'influxdbwriter')
    results['influx_data_buffer_items'] = compare_metric(influx_status['data_buffer_items'], options[:influx_warn], options[:influx_crit], 'influx_data_buffer_items')
    results['influx_work_queue_item_rate'] = compare_metric(influx_status['work_queue_item_rate'], options[:influx_warn], options[:influx_crit], 'influx_work_queue_item_rate')
    results['influx_work_queue_items'] = compare_metric(influx_status['work_queue_items'], options[:influx_warn], options[:influx_crit], 'influx_work_queue_items')
  end
  ido_status = get_status_values(status_object, 'IdoMysqlConnection', 'idomysqlconnection')
  app_status = get_status_values(status_object, 'IcingaApplication', 'icingaapplication')
  # status for ApiListener uses a different format / does not has multiple instances
  api_status = status_object['results'].select {|key| key['name'] == 'ApiListener'}[0]['status']['api']

  results['ido_query_queue_items'] = compare_metric(ido_status['query_queue_items'], options[:ido_warn], options[:ido_crit], 'ido_query_queue_items')
  results['ido_query_queue_item_rate'] = compare_metric(ido_status['query_queue_item_rate'], options[:ido_warn], options[:ido_crit], 'ido_query_queue_item_rate')
  results['api_num_not_conn_endpoints'] = compare_metric(
    api_status['num_not_conn_endpoints'],
    (api_status['num_conn_endpoints'] * 0.2).round,
    (api_status['num_conn_endpoints'] * 0.5).round,
    'num_not_conn_endpoints'
  )

  final_code = results.values.map { |i| i[:code] }.max
  if final_code == 0
    puts 'OK: ' + results.map{|k, v| v[:text]}.join(', ')
  else
    puts states[final_code] + ': ' + results.select {|k, v| v[:code] > 0}.map{|k, v| v[:text]}.join(', ')
  end
rescue
   puts "UNKNOWN: Exception in #{$0}"
   exit 3
end
exit final_code
