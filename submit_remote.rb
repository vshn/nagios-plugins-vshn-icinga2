#!/usr/bin/ruby

require 'net/http'
require 'uri'
require 'json'
require 'optparse'

options = {}
options[:port] = 5665

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"
  opts.on("-H", "--host=host", "=MANDATORY", String) do |v|
    options[:host] = v;
  end
  opts.on("-P", "--port=port", "=MANDATORY", Integer) do |v|
    options[:port] = v;
  end
  opts.on("-u", "--user=username", "=MANDATORY", String) do |v|
    options[:user] = v;
  end
  opts.on("-p", "--password=password", "=MANDATORY", String) do |v|
    options[:pass] = v;
  end
  opts.on("-c", "--command=command", "=MANDATORY", String) do |v|
    options[:command] = v;
  end
  opts.on("-s", "--remoteservice=host!service", "=MANDATORY", String) do |v|
    options[:remoteservice] = v;
  end
end.parse!
raise ArgumentError.new("Wrong number of options") unless options.keys.count == 6

begin
  cmd = options[:command]
  cmd_result = %x(#{cmd})
  cmd_code = $?.exitstatus

  unless cmd_result.empty?
    http = Net::HTTP.start(options[:host], options[:port], :use_ssl => true, :verify_mode => 0)
    data = {
      'exit_status' => cmd_code,
      'plugin_output' => cmd_result,
    }
    url = '/v1/actions/process-check-result?service=' + options[:remoteservice]
    request = Net::HTTP::Post.new(url, { 'Accept' => 'application/json' })
    request.basic_auth options[:user], options[:pass]
    request.body = data.to_json
    response = http.request(request)
    if response.code != '200'
      puts 'UNKNOWN: API call to ' + options[:host] + ' failed: ' + response.code + ' ' + response.message
      exit 3
    end
    output = JSON.parse(response.body)
    puts cmd_result
    exit cmd_code
  else
    puts 'UNKNOWN: No output from command. Not submitting to remote icinga.'
    exit 3
  end
rescue
  puts "UNKNOWN: Exception in #{$0}"
  exit 3
end
