require_relative '../../app/config.rb'
require_relative '../../app/world.rb'
require_relative '../../app/regions.rb'
require_relative '../../app/assets.rb'
require_relative '../../app/owl.rb'

# Owl.update needs args.state and the player; the follow maths itself does not,
# so the pure parts are checked directly against plain structs.
Player = Struct.new(:x, :depth, :heading_x)
Owl_   = Struct.new(:x, :depth, :speed, :mode, :lift, :facing, :flap_ticks)

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


puts 'it turns to look at the traveller, and holds a side profile'
owl = Owl_.new 640, 100.0, 0.0, :perched, 0, :east, 0
Owl.face_player owl, Player.new(200, 100.0, 1)
check 'looks west when he is to the west', owl.facing, :west
Owl.face_player owl, Player.new(1100, 100.0, 1)
check 'looks east when he is to the east', owl.facing, :east

puts 'the deadband stops it flicking as he walks along its x'
owl.facing = :east
Owl.face_player owl, Player.new(640 - (Config::OWL_FACING_DEADBAND_PX - 1), 100.0, 1)
check 'holds its facing for a small offset', owl.facing, :east
Owl.face_player owl, Player.new(640 - (Config::OWL_FACING_DEADBAND_PX + 1), 100.0, 1)
check 'turns for a clear one', owl.facing, :west

puts 'the wingbeat runs in the air and resets on landing'
owl = Owl_.new 0, 0.0, 0.0, :flying, 0, :east, 0
Config::OWL_FLAP_TICKS.times { Owl.beat_wings owl }
check 'first half of the stroke', Owl.flap_progress(owl) >= 0.5, true
check 'still one cycle',          Owl.flap_progress(owl) < 1.0,  true

Owl.beat_length.times { Owl.beat_wings owl }
check 'wraps rather than growing', Owl.flap_progress(owl), 0.5

owl.mode = :perched
Owl.beat_wings owl
check 'a perched owl holds one pose', owl.flap_ticks, 0

puts 'each pose it can be in resolves to art that exists'
[:perched, :flying].each do |mode|
  [:east, :west].each do |facing|
    owl.mode   = mode
    owl.facing = facing
    name = Owl.sprite_name owl
    paths = Assets.descriptor(name, :myth)[:paths]
    check "#{name} files exist",
          paths.all? { |path| File.exist? File.join(__dir__, '../..', path) }, true
  end
end

puts 'the owl is drawn owl-sized, not person-sized'
w, h = Assets.draw_size :owl_perched_east, :myth
check 'shorter than the traveller', h < Config::CHARACTER_HEIGHT_PX, true
check 'and the player is unaffected',
      Assets.draw_size(:player_walk, :myth)[1] > h, true

puts
puts $failures.zero? ? 'check_owl: PASSED' : "check_owl: #{$failures} FAILED"
exit($failures.zero? ? 0 : 1)
