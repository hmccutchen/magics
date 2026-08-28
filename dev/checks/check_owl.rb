require_relative '../../app/config.rb'
require_relative '../../app/world.rb'
require_relative '../../app/regions.rb'
require_relative '../../app/assets.rb'
require_relative '../../app/owl.rb'

# Stand-ins for DragonRuby's args, which is an open structure. Only the fields
# Owl actually reads are modelled.
Player   = Struct.new(:x, :depth, :heading_x)
Perch    = Struct.new(:x, :depth, :h)

class FakeOwl
  attr_accessor :x, :depth, :fw, :fd, :mode, :speed, :facing, :flap_ticks,
                :lift, :perch_kind, :perch_index, :soar_until, :perch_until

  def initialize x, depth
    @x           = x
    @depth       = depth
    @fw          = Config::OWL_FW
    @fd          = Config::OWL_FD
    @mode        = :soaring
    @speed       = 0.0
    @facing      = :east
    @flap_ticks  = 0
    @lift        = Config::OWL_SOAR_LIFT
    @perch_kind  = nil
    @perch_index = 0
    @soar_until  = 0
    @perch_until = 0
  end
end

class FakeState
  attr_accessor :tick_count, :owl, :player, :pushables, :creature,
                :resolved_regions

  def initialize
    @tick_count       = 0
    @resolved_regions = []
    @player           = Player.new 640, 100.0, 1
    @owl              = FakeOwl.new 640, 126.0
    @pushables        = [Perch.new(700, 110.0, 40), Perch.new(200, 60.0, 40)]
    @creature         = Perch.new 500, 130.0, Config::CREATURE_H
  end
end

class FakeArgs
  attr_reader :state

  def initialize
    @state = FakeState.new
  end

  # Run n ticks of the real update, so these check the state machine as it
  # actually runs rather than the methods it happens to be built from.
  def run n = 1
    n.times do
      @state.tick_count += 1
      Owl.update self
    end
  end

  # Advance to whichever timer the owl is currently waiting on, so a check
  # does not have to sit through a randomised span in real ticks.
  def expire_timer!
    @state.tick_count = [@state.owl.soar_until, @state.owl.perch_until].max + 1
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

def close label, got, want, tolerance = 0.001
  check label, (got - want).abs <= tolerance, true
end

# Runs the owl until it reaches a mode, or gives up. Returns whether it got
# there, so a check can assert on arrival rather than on a tick count.
def run_until args, mode, limit = 4000
  limit.times do
    return true if args.state.owl.mode == mode

    args.run
  end

  args.state.owl.mode == mode
end

puts 'tuning constants pass their own load-time guards'

puts 'the anchor sits behind the player and swaps sides with his heading'
facing_right = Owl.anchor_for Player.new(640, 100.0, 1)
facing_left  = Owl.anchor_for Player.new(640, 100.0, -1)
check 'behind him when facing right', facing_right[0] < 640, true
check 'behind him when facing left',  facing_left[0]  > 640, true
close 'mirrored about the player', (facing_right[0] + facing_left[0]) / 2.0, 640.0

puts 'the anchor stays inside the world'
edge = Owl.anchor_for Player.new(Config::SCREEN_W - 4, Config::DEPTH_FAR, -1)
check 'x clamped on stage',    edge[0] <= Config::SCREEN_W, true
check 'depth clamped in band', edge[1] <= Config::DEPTH_FAR, true

puts 'it soars by default, and stays up there'
args = FakeArgs.new
args.state.owl.soar_until = 10_000        # not ready to land yet
args.run 120
check 'still soaring',    args.state.owl.mode, :soaring
close 'at soaring height', args.state.owl.lift, Config::OWL_SOAR_LIFT, 1.0
check 'wings still',      args.state.owl.flap_ticks, 0

puts 'it will not land on the traveller'
args = FakeArgs.new
kinds = Owl.perchables(args).map { |p| p[:kind] }.uniq.sort
check 'only things in the world', kinds, [:creature, :pushable]

puts 'it keeps soaring when there is nothing near him worth landing on'
args = FakeArgs.new
args.state.player.x     = 640
args.state.player.depth = 100.0
# Well beyond the reach measured FROM HIM, not merely a large x.
far = 640 + Config::OWL_PERCH_REACH + 100
args.state.pushables.each { |p| p.x = far }
args.state.creature.x = far
args.expire_timer!
args.run
check 'nothing chosen',   Owl.choose_perch(args), nil
check 'and it stays up',  args.state.owl.mode, :soaring
check 'timer reset',      args.state.owl.soar_until > args.state.tick_count, true

puts 'when something IS near him, it comes down and lands on it'
args = FakeArgs.new
args.expire_timer!
args.run
check 'heading down', args.state.owl.mode, :descending
check 'wings beating', Owl.flapping?(args.state.owl), true

check 'it gets there', run_until(args, :perched), true
perch = Owl.perch_entity args, args.state.owl
close 'over the perch', args.state.owl.x,     perch.x, Config::OWL_ARRIVE_DISTANCE
close 'at its depth',   args.state.owl.depth, perch.depth, Config::OWL_ARRIVE_DISTANCE
close 'sitting on top', args.state.owl.lift,  Owl.perch_lift(perch), Config::OWL_LIFT_ARRIVED_PX
check 'wings folded',   Owl.flapping?(args.state.owl), false
check 'perched pose',   Owl.sprite_name(args.state.owl).to_s.include?('perched'), true

puts 'it rides whatever it is sitting on'
before = [args.state.owl.x, args.state.owl.depth]
perch.x     += 90
perch.depth += 25.0
args.run
check 'carried along in x',     args.state.owl.x,     perch.x
check 'and in depth',           args.state.owl.depth, perch.depth
check 'which is a real change', [args.state.owl.x, args.state.owl.depth] == before, false

puts 'it leaves when it has sat long enough'
args.state.player.x     = perch.x        # keep him close, so only the timer ends it
args.state.player.depth = perch.depth
args.state.owl.perch_until = args.state.tick_count
args.run
check 'climbing away', args.state.owl.mode, :climbing
check 'perch let go',  args.state.owl.perch_kind, nil

puts 'and it climbs back up to soaring'
check 'gets back up',  run_until(args, :soaring), true
close 'to soaring height', args.state.owl.lift, Config::OWL_SOAR_LIFT, Config::OWL_LIFT_ARRIVED_PX
check 'gliding again',  Owl.flapping?(args.state.owl), false
check 'soaring pose',   Owl.sprite_name(args.state.owl).to_s.include?('soaring'), true

puts 'following beats sitting: it leaves early if he walks off'
args = FakeArgs.new
args.expire_timer!
args.run
run_until args, :perched
args.state.owl.perch_until = args.state.tick_count + 100_000   # would sit forever
args.state.player.x = 40                                       # but he has gone
args.run
check 'goes after him', args.state.owl.mode, :climbing

puts 'a perch that vanishes does not strand it'
args = FakeArgs.new
args.expire_timer!
args.run
run_until args, :perched
args.state.pushables = []
args.state.creature  = nil
args.run
check 'climbs away instead', args.state.owl.mode, :climbing

puts 'it turns to look at the traveller, and holds a side profile'
owl = FakeOwl.new 640, 100.0
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

puts 'wings beat only on the way down and the way back up'
owl = FakeOwl.new 0, 0.0
{ soaring: false, perched: false, descending: true, climbing: true }.each do |mode, flaps|
  owl.mode = mode
  check "#{mode}", Owl.flapping?(owl), flaps
end

puts 'the wingbeat wraps rather than growing, and resets when it stops'
owl.mode = :descending
Owl.beat_wings owl
check 'first half of the stroke', Owl.flap_progress(owl) < 0.5, true
Owl.beat_length.times { Owl.beat_wings owl }
check 'wrapped',                  Owl.flap_progress(owl) < 1.0, true
owl.mode = :soaring
Owl.beat_wings owl
check 'reset when gliding',       owl.flap_ticks, 0

puts 'a perch is taller at the front of the stage than at the back'
near = Owl.perch_lift Perch.new(0, Config::DEPTH_NEAR, 40)
far  = Owl.perch_lift Perch.new(0, Config::DEPTH_FAR,  40)
check 'nearer is higher', near > far, true

puts 'every pose it can be in resolves to art that exists'
owl = FakeOwl.new 0, 0.0
[:soaring, :perched, :descending, :climbing].each do |mode|
  [:east, :west].each do |facing|
    owl.mode   = mode
    owl.facing = facing
    name  = Owl.sprite_name owl
    paths = Assets.descriptor(name, :myth)[:paths]
    check "#{mode}/#{facing} -> #{name}",
          paths.all? { |path| File.exist? File.join(__dir__, '../..', path) }, true
  end
end

puts 'the owl is drawn owl-sized, not person-sized'
soar_h   = Assets.draw_size(:owl_soaring_east, :myth)[1]
perch_h  = Assets.draw_size(:owl_perched_east, :myth)[1]
check 'shorter than the traveller', perch_h < Config::CHARACTER_HEIGHT_PX, true
check 'and the same scale in every pose', soar_h, perch_h

puts
puts $failures.zero? ? 'check_owl: PASSED' : "check_owl: #{$failures} FAILED"
exit($failures.zero? ? 0 : 1)
