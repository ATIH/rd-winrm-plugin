#!/usr/bin/ruby
require 'winrm'
user = ENV['RD_CONFIG_USER'].dup # for some reason these strings is frozen, so we duplicate it
pass = ENV['RD_CONFIG_PASS'].dup
host = ENV['RD_NODE_HOSTNAME']
port = ENV['RD_CONFIG_WINRMPORT']
shell = ENV['RD_CONFIG_SHELL']
realm = ENV['RD_CONFIG_KRB5_REALM']
command = ENV['RD_EXEC_COMMAND']
override = ENV['RD_CONFIG_ALLOWOVERRIDE']
host = ENV['RD_OPTION_WINRMHOST'] if ENV['RD_OPTION_WINRMHOST'] && (override == 'host' || override == 'all')
user = ENV['RD_OPTION_WINRMUSER'].dup if ENV['RD_OPTION_WINRMUSER'] && (override == 'user' || override == 'all')
pass = ENV['RD_OPTION_WINRMPASS'].dup if ENV['RD_OPTION_WINRMPASS'] && (override == 'user' || override == 'all')
auth = ENV['RD_CONFIG_AUTHTYPE']
proto = (auth == 'ssl') ? "https" : "http"

ooutput = ''
eoutput = ''

# Wrapper to fix: "not setting executing flags by rundeck for 2nd file in plugin"
# # https://github.com/rundeck/rundeck/issues/1421
# remove it after issue will be fixed
if File.exist?("#{ENV['RD_PLUGIN_BASE']}/winrmcp.rb") && !File.executable?("#{ENV['RD_PLUGIN_BASE']}/winrmcp.rb")
  File.chmod(0764, "#{ENV['RD_PLUGIN_BASE']}/winrmcp.rb")
end

# Wrapper ro avoid strange and undocumented behavior of rundeck
# Should be deleted after rundeck fix
# https://github.com/rundeck/rundeck/issues/602
command = command.gsub(/'"'"'' /, '\'')
command = command.gsub(/ ''"'"'/, '\'')
command = command.gsub(/ '"/, '"')
command = command.gsub(/"' /, '"')

# Wrapper for avoid unix style file copying then scripts run
# - not accept chmod call
# - replace rm -f into rm -force
# - auto copying renames file from .sh into .ps1, .bat or .wql in tmp directory
exit 0 if command.include? 'chmod +x /tmp/'

if command.include? 'rm -f /tmp/'
  shell = 'powershell'
  command = command.gsub(%r{rm -f /tmp/}, 'rm -force /tmp/')
end

if %r{/tmp/.*\.sh}.match(command)
  case shell
  when 'powershell'
    command = command.gsub(/\.sh/, '.ps1')
  when 'cmd'
    command = command.gsub(/\.sh/, '.bat')
  when 'wql'
    command = command.gsub(/\.sh/, '.wql')
  end
end

if ENV['RD_JOB_LOGLEVEL'] == 'DEBUG'
  puts 'variables:'
  puts "realm => #{realm}"
  puts "endpoint => #{proto}://#{host}:#{port}/wsman"
  puts "user => #{user}"
  puts 'pass => ********'
  # puts "pass => #{pass}" # uncomment it for full auth debugging
  puts "command => #{ENV['RD_EXEC_COMMAND']}"
  puts "newcommand => #{command}"
  puts ''

  puts 'ENV:'
  ENV.each do |k, v|
    puts "#{k} => #{v}" if v != pass && k != 'RD_CONFIG_PASS'
    puts "#{k} => ********" if v == pass || k == 'RD_CONFIG_PASS'
    # puts "#{k} => #{v}" if v == pass # uncomment it for full auth debugging
  end
end

def stderr_text(stderr)
  doc = REXML::Document.new(stderr)
  begin
    text = doc.root.get_elements('//S').map(&:text).join
    text.gsub(/_x(\h\h\h\h)_/) do
      code = Regexp.last_match[1]
      code.hex.chr
    end
  rescue
    return stderr
  end
end

conn_opts = {
  endpoint: "#{proto}://#{host}:#{port}/wsman",
  user: user,
  password: pass,
  disable_sspi: true
}

case auth
when 'kerberos'
  transport = :ssl
when 'plaintext'
  transport = :plaintext
when 'ssl'
  transport = :ssl
else
  fail "Invalid authtype '#{auth}' specified, expected: kerberos, plaintext, ssl."
end

conn_opts = conn_opts.merge( { transport: transport } )
conn_opts = conn_opts.merge( { ca_trust_path: ENV['RD_CONFIG_CA_TRUST_PATH']}) if ENV['RD_CONFIG_CA_TRUST_PATH'] && transport == :ssl

conn_opts = conn_opts.merge( { operation_timeout: ENV['RD_CONFIG_WINRMTIMEOUT'].to_i } ) if ENV['RD_CONFIG_WINRMTIMEOUT']


if ENV['RD_JOB_LOGLEVEL'] == 'DEBUG'
  puts "Connection options :"
  conn_opts_pwmask = conn_opts.clone
  conn_opts_pwmask[:password] = "***********"
  puts conn_opts_pwmask.inspect
end

winrm = WinRM::Connection.new(conn_opts)

case shell
when 'powershell'
  result = winrm.shell(:powershell).run(command)
when 'cmd'
  result = winrm.shell(:cmd).run(command)
when 'wql'
  result = winrm.run_wql(command)
end


print result.output

exit result.exitcode if result.exitcode != 0
