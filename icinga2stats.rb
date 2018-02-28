#!/usr/bin/ruby

require 'net/http'
require 'uri'
require 'json'
require 'optparse'

options = {}
options[:port] = 5665
options[:managed_var] = 'vshnmanaged'

OptionParser.new do |opts|
  opts.banner = "Usage: icinga2stats.rb [options]"
  opts.on("-H", "--host=host" , String) do |v|
    options[:host] = v;
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
  opts.on("-f", "--filter=filter", String) do |v|
    options[:managed_var] = v;
  end
end.parse!

datapoints = {
  'num_hosts_up' => {
    'filter' => 'host.state==0 && host.vars.' + options[:managed_var].to_s + '!=false',
    'url' => '/v1/objects/hosts',
  },
  'num_hosts_down' => {
    'filter' => 'host.state_type==1 && host.state!=0 && host.downtime_depth==0 && host.acknowledgement==0' +
      '&& host.vars.' + options[:managed_var].to_s + '!=false',
    'url' => '/v1/objects/hosts',
  },
  'num_services_ok_filtered' => {
    'filter' => 'service.state==0 && service.vars.' + options[:managed_var].to_s + '==false',
    'url' => '/v1/objects/services',
  },
  'num_services_critical' => {
    'filter' => 'service.state_type==1 && service.state==2 && service.downtime_depth==0 && service.acknowledgement==0 && host.state==0' +
      '&& service.vars.' + options[:managed_var].to_s + '!=false',
    'url' => '/v1/objects/services',
  },
  'num_services_warning' => {
    'filter' => 'service.state_type==1 && service.state==1 && service.downtime_depth==0 && service.acknowledgement==0 && host.state==0' +
      '&& service.vars.' + options[:managed_var].to_s + '!=false',
    'url' => '/v1/objects/services',
  }
}

header = {
  "Accept" => "application/json",
  "X-HTTP-Method-Override" => "GET"
}
begin
  # Create the HTTP objects
  http = Net::HTTP.start(options[:host], options[:port], :use_ssl => true, :verify_mode => 0)
  results = {}

  datapoints.each do |key, value|
    data = {
      'filter' => value['filter'],
      'attrs' => [ 'name' ]
    }
    request = Net::HTTP::Post.new(value['url'], header)
    request.basic_auth options[:user], options[:pass]
    request.body = data.to_json
    response = http.request(request)
    output = JSON.parse(response.body)
    results[key] = output['results'].length
  end

  # get okay services the quick way (all ok minus filtered)
  request = Net::HTTP::Get.new('/v1/status/CIB', header)
  request.basic_auth options[:user], options[:pass]
  response = http.request(request)
  output = JSON.parse(response.body)
  services_ok = output['results'][0]['status']['num_services_ok']

  results['num_services_ok'] = services_ok - results['num_services_ok_filtered']

  perf_data = []
  results.each do |key, value|
    perf_data.push(key + "=" + value.to_s)
  end

  puts 'OK: Stats collected |' + perf_data.join(' ')
  exit 0
rescue
  puts 'UNKNOWN: An error occured, please run the check manually to see what it wrong'
  exit 3
end
