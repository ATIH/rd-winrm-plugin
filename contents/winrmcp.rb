#!/usr/bin/ruby
require 'winrm-fs'
user = ENV['RD_CONFIG_USER'].dup # for some reason these strings is frozen, so we duplicate it
pass = ENV['RD_CONFIG_PASS'].dup
host = ENV['RD_NODE_HOSTNAME']
port = ENV['RD_CONFIG_WINRMPORT']
shell = ENV['RD_CONFIG_SHELL']
realm = ENV['RD_CONFIG_KRB5_REALM']
override = ENV['RD_CONFIG_ALLOWOVERRIDE']
host = ENV['RD_OPTION_WINRMHOST'] if ENV['RD_OPTION_WINRMHOST'] && (override == 'host' || override == 'all')
user = ENV['RD_OPTION_WINRMUSER'].dup if ENV['RD_OPTION_WINRMUSER'] && (override == 'user' || override == 'all')
pass = ENV['RD_OPTION_WINRMPASS'].dup if ENV['RD_OPTION_WINRMPASS'] && (override == 'user' || override == 'all')
auth = ENV['RD_CONFIG_AUTHTYPE']
proto = (auth == 'ssl') ? "https" : "http"

file = ARGV[1]
dest = ARGV[2]

# Wrapper to fix: "not setting executing flags by rundeck for 2nd file in plugin"
# # https://github.com/rundeck/rundeck/issues/1421
# remove it after issue will be fixed
if File.exist?("#{ENV['RD_PLUGIN_BASE']}/winrmexe.rb") && !File.executable?("#{ENV['RD_PLUGIN_BASE']}/winrmexe.rb")
  File.chmod(0764, "#{ENV['RD_PLUGIN_BASE']}/winrmexe.rb") # https://github.com/rundeck/rundeck/issues/1421
end

# Wrapper for avoid unix style file copying then scripts run
# - not accept chmod call
# - replace rm -f into rm -force
# - auto copying renames file from .sh into .ps1, .bat or .wql in tmp directory
if %r{/tmp/.*\.sh}.match(dest)
  case shell
  when 'powershell'
    dest = dest.gsub(/\.sh/, '.ps1')
  when 'cmd'
    dest = dest.gsub(/\.sh/, '.bat')
  when 'wql'
    dest = dest.gsub(/\.sh/, '.wql')
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
  conn_opts_pwmask = conn_opts
  conn_opts["password"] = "***********"
  puts conn_opts_pwmask.inspect
end

winrm = WinRM::Connection.new(conn_opts)

file_manager = WinRM::FS::FileManager.new(winrm)

## upload file
file_manager.upload(file, dest)

## upload the entire contents of my_dir to c:/foo/my_dir
# file_manager.upload('/Users/sneal/my_dir', 'c:/foo/my_dir')

## upload the entire directory contents of foo to c:\program files\bar
# file_manager.upload('/Users/sneal/foo', '$env:ProgramFiles/bar')

#file_manager.upload('/home/brice/index.htm', 'D:/')
