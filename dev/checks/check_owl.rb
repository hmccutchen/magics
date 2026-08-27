require_relative '../../app/config.rb'
require_relative '../../app/world.rb'
require_relative '../../app/owl.rb'

# Owl.update needs args.state and the player; the follow maths itself does not,
# so the pure parts are checked directly against plain structs.
Player = Struct.new(:x, :depth, :heading_x)
Owl_   = Struct.new(:x, :depth, :speed, :mode, :lift)

$failures = 0

def check label, got, want
  if got == want
    puts "  PASS  #{label}"
  else
    puts "  FAIL  #{label}  (got #{got.inspect}, want #{want.inspect})"
    $failures += 1
  end
end

def close label, got, want, tolerance = 0.001
  check label, (got - want).abs <= tolerance, true
end

# Loading owl.rb at all runs its three load-time guards, so reaching this line
# is itself the check that the tuned constants cannot orbit or twitch.
puts 'tuning constants pass their own load-time guards'

puts 'the anchor sits behind the player and swaps sides with his heading'
facing_right = Owl.anchor_for Player.new(640, 100.0, 1)
facing_left  = Owl.anchor_for Player.new(640, 100.0, -1)
check 'behind him when facing right', facing_right[0] < 640, true
check 'behind him when facing left',  facing_left[0]  > 640, true
close 'mirrored about the player', (facing_right[0] + facing_left[0]) / 2.0, 640.0

puts 'the anchor stays inside the world'
edge = Owl.anchor_for Player.new(Config::SCREEN_W - 4, Config::DEPTH_FAR, -1)
check 'x clamped on stage',   edge[0] <= Config::SCREEN_W, true
check 'depth clamped in band', edge[1] <= Config::DEPTH_FAR, true

puts 'it stays perched until the gap is worth crossing'
owl = Owl_.new 640, 100.0, 0.0, :perched, Config::OWL_PERCH_LIFT
Owl.consider_taking_off owl, [640 + (Config::OWL_SLACK_RADIUS / 2), 100.0]
check 'ignores a small gap', owl.mode, :perched

Owl.consider_taking_off owl, [640 + Config::OWL_SLACK_RADIUS + 10, 100.0]
check 'takes off for a large one', owl.mode, :flying

puts 'it closes the gap and perches again'
owl    = Owl_.new 200, 100.0, 0.0, :flying, Config::OWL_FLIGHT_LIFT
anchor = [900, 140.0]
before = Owl.distance_to owl, anchor

600.times { Owl.fly owl, anchor if owl.mode == :flying }

check 'ends perched',       owl.mode, :perched
check 'closed the distance', Owl.distance_to(owl, anchor) < before, true
check 'arrived, not orbiting',
      Owl.distance_to(owl, anchor) <= Config::OWL_ARRIVE_DISTANCE, true

puts 'drawn height eases between perch and flight without overshooting'
owl = Owl_.new 0, 0.0, 0.0, :flying, Config::OWL_PERCH_LIFT
400.times { Owl.ease_lift owl }
check 'never passes the flight height', owl.lift <= Config::OWL_FLIGHT_LIFT, true
close 'reaches the flight height', owl.lift, Config::OWL_FLIGHT_LIFT, 0.5

owl.mode = :perched
400.times { Owl.ease_lift owl }
check 'never drops below the perch height', owl.lift >= Config::OWL_PERCH_LIFT, true
close 'returns to the perch height', owl.lift, Config::OWL_PERCH_LIFT, 0.5

puts
puts $failures.zero? ? 'check_owl: PASSED' : "check_owl: #{$failures} FAILED"
exit($failures.zero? ? 0 : 1)
