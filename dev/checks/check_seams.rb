require_relative '../../app/config.rb'
require_relative '../../app/world.rb'
require_relative '../../app/regions.rb'
require_relative '../../app/seams.rb'

# Minimal stand-in for DragonRuby's args.state, which is an open structure.
class FakeState
  attr_accessor :resolved_regions, :revealed_seams
end

class FakeArgs
  attr_reader :state

  def initialize
    @state = FakeState.new
  end
end

$failures = 0

def check label, got, want
  if got == want
    puts "  PASS  #{label}"
  else
    puts "  FAIL  #{label}  (got #{got.inspect}, want #{want.inspect})"
    $failures += 1
  end
end

# Loading seams.rb at all runs assert_one_per_region! and
# assert_inside_declared_region!, so reaching this line is itself the check
# that the authored table is coherent.
puts 'authored table passes its own load-time guards'
check 'at least one seam declared', Seams::SEAMS.length >= 1, true

puts 'every seam sits in the region it declares'
Seams::SEAMS.each do |seam|
  check "#{seam[:region]} placement",
        Regions.at(seam[:x], seam[:depth])[:name],
        seam[:region]
end

puts 'revealing'
args = FakeArgs.new
check 'starts hidden',      Seams.revealed?(args, :far_stand), false
Seams.reveal! args, :far_stand
check 'revealed after reveal!', Seams.revealed?(args, :far_stand), true
Seams.reveal! args, :far_stand
check 'reveal! is idempotent', args.state.revealed_seams, [:far_stand]
check 'other regions unaffected', Seams.revealed?(args, :fern_hollow), false

# Repaired is DERIVED, never stored: a repaired seam is a resolved region.
# This is the assumption assert_one_per_region! exists to protect.
puts 'repairing is the region resolving'
check 'not repaired yet', Regions.resolved?(args, :far_stand), false
Regions.resolve! args, :far_stand
check 'repaired',         Regions.resolved?(args, :far_stand), true
check 'tier follows',     Regions.tier_at(args, 1000, 250.0), :truth

puts
puts $failures.zero? ? 'check_seams: PASSED' : "check_seams: #{$failures} FAILURE(S)"
exit($failures.zero? ? 0 : 1)
