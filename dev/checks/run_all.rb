# Runs every pure-logic harness under dev/checks.
#
# These run in plain MRI Ruby, NOT in DragonRuby's mruby. They check logic,
# never runtime compatibility -- mruby has silently returned nil from methods
# MRI accepts. Passing here does not mean the game runs. Boot the engine too.
require 'rbconfig'

failures = 0

Dir[File.join(__dir__, 'check_*.rb')].sort.each do |path|
  puts "== #{File.basename path}"
  system(RbConfig.ruby, path) || failures += 1
end

puts
puts failures.zero? ? 'ALL CHECKS PASSED' : "#{failures} CHECK FILE(S) FAILED"
exit(failures.zero? ? 0 : 1)
