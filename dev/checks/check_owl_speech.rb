require_relative '../../app/config.rb'
require_relative '../../app/world.rb'
require_relative '../../app/regions.rb'
require_relative '../../app/seams.rb'
require_relative '../../app/assets.rb'
require_relative '../../app/renderer.rb'
require_relative '../../app/owl.rb'
require_relative '../../app/pushable.rb'
require_relative '../../app/pattern.rb'
require_relative '../../app/owl_speech.rb'

# Minimal stand-ins for DragonRuby's args, which is an open structure. Only
# the parts OwlSpeech actually reads are modelled.
# The owl is drawn from art now, so it has no w/h of its own -- its size comes
# from the tier descriptor. Only the fields OwlSpeech and Owl.drawable read.
class FakeOwl
  attr_accessor :x, :depth, :lift, :mode, :facing, :flap_ticks

  def initialize
    @x          = 640
    @depth      = 100.0
    @lift       = Config::OWL_SOAR_LIFT
    @mode       = :soaring
    @facing     = :east
    @flap_ticks = 0
  end
end

# The owl records where the player stood and how much of the world he had
# taken apart, so both have to exist for a firing to be logged.
class FakePlayer
  attr_accessor :x, :depth

  def initialize
    @x     = 100        # :fern_hollow
    @depth = 40.0
  end
end

class FakePushable
  attr_accessor :x, :depth

  def initialize x, depth
    @x     = x
    @depth = depth
  end
end

class FakeState
  attr_accessor :resolved_regions, :revealed_seams, :seams, :tick_count,
                :owl, :player, :pushables,
                :owl_line, :owl_line_until, :owl_log, :owl_seen_seams

  def initialize
    @resolved_regions = []
    @revealed_seams   = []
    @tick_count       = 0
    @owl              = FakeOwl.new
    @player           = FakePlayer.new
    @pushables        = Pushable::PUSHABLES.map { |p| FakePushable.new p[:x], p[:depth] }
    @owl_line_until   = 0
    @owl_log          = []
    @owl_seen_seams   = []
  end

  # Seat the object that fits the socket, which is what "a pattern has been
  # completed" means to Pattern.
  def complete_the_pattern!
    socket = Pattern::SOCKETS[0]
    @pushables[socket[:filled_by]].x     = socket[:x]
    @pushables[socket[:filled_by]].depth = socket[:depth]
  end
end

# A click is a point that answers inside_rect?, which DragonRuby mixes into
# Hash via Geometry. Reimplemented here because that mixin is engine-side.
class FakeClick
  attr_reader :x, :y

  def initialize x, y
    @x = x
    @y = y
  end

  def inside_rect? rect
    @x >= rect[:x] && @x <= rect[:x] + rect[:w] &&
      @y >= rect[:y] && @y <= rect[:y] + rect[:h]
  end
end

class FakeMouse
  attr_accessor :click
end

class FakeInputs
  attr_reader :mouse

  def initialize
    @mouse = FakeMouse.new
  end
end

class FakeArgs
  attr_reader :state, :inputs

  def initialize
    @state  = FakeState.new
    @inputs = FakeInputs.new
  end

  # One tick, with an optional click this frame. Clicks are momentary in
  # DragonRuby, so it is cleared afterwards the way the engine would.
  def tick click = nil
    @inputs.mouse.click = click
    @state.tick_count  += 1
    OwlSpeech.update self
    @inputs.mouse.click = nil
  end

  def shut_up!
    @state.owl_line = nil
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

# The centre of the owl's drawn rect, which is what a player aims at.
def owl_centre args
  rect = Renderer.sprite_rect args, Owl.drawable(args)

  FakeClick.new rect[:x] + (rect[:w] / 2), rect[:y] + (rect[:h] / 2)
end

puts 'loading the file runs assert_every_referenced_line_exists!'
check 'every referenced line is real',
      (OwlSpeech::STORY_TRIGGERS.values + [OwlSpeech::IDLE_LINE])
        .all? { |id| OwlSpeech::LINES.key? id },
      true

puts 'the owl says nothing unbidden'
args = FakeArgs.new
30.times { args.tick }
check 'silent while nothing happens', OwlSpeech.speaking?(args), false

puts 'walking about does not make it talk'
args = FakeArgs.new
args.state.owl.x = 100
args.tick
args.state.owl.x = 900
args.tick
check 'still silent', OwlSpeech.speaking?(args), false

puts 'clicking it makes it speak'
args = FakeArgs.new
args.tick owl_centre(args)
check 'speaking',              OwlSpeech.speaking?(args), true
check 'nothing to hint about', args.state.owl_line, OwlSpeech::IDLE_LINE

puts 'clicking elsewhere does not'
args = FakeArgs.new
args.tick FakeClick.new(10, 10)
check 'silent', OwlSpeech.speaking?(args), false

puts 'the padding makes it a fair target'
args   = FakeArgs.new
owl    = args.state.owl
owl.depth = Config::DEPTH_FAR          # smallest the bird ever draws
rect   = Renderer.sprite_rect args, Owl.drawable(args)
just_outside = FakeClick.new rect[:x] - (Config::OWL_CLICK_PADDING_PX - 1), rect[:y]
args.tick just_outside
check 'a near miss still counts', OwlSpeech.speaking?(args), true

puts 'a revealed seam makes it offer the hint unprompted'
args = FakeArgs.new
args.tick
Seams.reveal! args, :far_stand
args.tick
check 'speaking',      OwlSpeech.speaking?(args), true
check 'the doc\'s line', args.state.owl_line, :fool_reaches

puts 'the hint is offered once, not every tick'
args.shut_up!
60.times { args.tick }
check 'said exactly once', OwlSpeech.firings(args, :fool_reaches).length, 1

puts 'asking again while the seam is still unactivated repeats the hint'
args.tick owl_centre(args)
check 'the same line, verbatim', args.state.owl_line, :fool_reaches
check 'both firings recorded',   OwlSpeech.firings(args, :fool_reaches).length, 2

puts 'once the seam is activated there is nothing left to hint'
args.shut_up!
Regions.resolve! args, :far_stand
args.tick owl_centre(args)
check 'falls back to the idle line', args.state.owl_line, OwlSpeech::IDLE_LINE

puts 'a story hint is never dropped for being badly timed'
args = FakeArgs.new
args.tick owl_centre(args)                 # owl is mid-idle-line
check 'busy saying something else', args.state.owl_line, OwlSpeech::IDLE_LINE

Seams.reveal! args, :far_stand
args.tick
check 'hint did not barge in',  args.state.owl_line, OwlSpeech::IDLE_LINE
check 'and was not consumed',   args.state.owl_seen_seams, []

args.state.tick_count = args.state.owl_line_until
args.tick
check 'it lands as soon as the owl is free', args.state.owl_line, :fool_reaches
check 'edge consumed only now', args.state.owl_seen_seams, [:far_stand]

puts 'it finishes its thought rather than being interrupted'
args = FakeArgs.new
args.tick owl_centre(args)
args.tick owl_centre(args)
check 'one firing, not two', args.state.owl_log.length, 1

puts 'the line expires on its own'
args.state.tick_count = args.state.owl_line_until
OwlSpeech.expire args
check 'silent again', OwlSpeech.speaking?(args), false

puts 'every firing records what the player had lived through'
args = FakeArgs.new
args.tick owl_centre(args)
first = args.state.owl_log.last
check 'the line id',        first[:line],       OwlSpeech::IDLE_LINE
check 'what set it off',    first[:trigger],    :clicked
check 'which hearing',      first[:occurrence], 1
check 'nothing resolved',   first[:regions_resolved],   []
check 'nothing revealed',   first[:seams_revealed],     []
check 'no patterns done',   first[:patterns_completed], 0
check 'where he stood',     first[:standing_in], :fern_hollow
check 'and his fidelity',   first[:player_tier], :myth

puts 'a repeated line is logged again, against the world as it then stands'
args = FakeArgs.new
args.state.player.x     = 900               # :east_clearing
args.state.player.depth = 40.0
Seams.reveal! args, :far_stand
args.tick                                   # the hint, offered unprompted
early = args.state.owl_log.last
check 'first hearing',        early[:occurrence],         1
check 'nothing resolved yet', early[:regions_resolved],   []
check 'no patterns done yet', early[:patterns_completed], 0
check 'in the clearing',      early[:standing_in],        :east_clearing
check 'drawn as myth',        early[:player_tier],        :myth

# Now the player lives through some of the world: he completes the pattern,
# admits the truth of a region, and walks into it -- so the very same words
# land against a different world, and a different him.
#
# far_stand's seam is deliberately left UNACTIVATED, since that is what keeps
# the hint applicable. fern_hollow is resolved directly as a fixture: it
# stands in for a second seam elsewhere in the world, which the authored
# SEAMS table does not hold yet.
args.shut_up!
args.state.complete_the_pattern!
Regions.resolve! args, :fern_hollow
args.state.player.x     = 100               # :fern_hollow, now resolved
args.state.player.depth = 40.0
args.tick owl_centre(args)

late = args.state.owl_log.last
check 'the same line, verbatim', late[:line], early[:line]
check 'second hearing',          late[:occurrence], 2
check 'more admitted',           late[:regions_resolved].length > early[:regions_resolved].length, true
check 'a pattern completed',     late[:patterns_completed], 1
check 'somewhere else',          late[:standing_in], :fern_hollow
check 'and drawn as truth now',  late[:player_tier], :truth

puts 'the log is chronological and inspectable'
check 'both hearings kept', OwlSpeech.firings(args, early[:line]).length, 2
check 'in the order heard',
      OwlSpeech.firings(args, early[:line]).map { |e| e[:occurrence] }, [1, 2]

puts 'a debug print of that history, for the eye rather than an assertion:'
OwlSpeech.dump args

puts 'text is kept on stage near the screen edges'
wide = 400.0
check 'left edge',
      OwlSpeech.label_x(0, wide), Config::OWL_SPEECH_MARGIN + (wide / 2)
check 'right edge',
      OwlSpeech.label_x(Config::SCREEN_W, wide),
      Config::SCREEN_W - Config::OWL_SPEECH_MARGIN - (wide / 2)
check 'left alone in the middle', OwlSpeech.label_x(640, wide), 640
check 'a line wider than the screen is centred',
      OwlSpeech.label_x(100, Config::SCREEN_W + 200), Config::SCREEN_W / 2.0

puts
puts $failures.zero? ? 'check_owl_speech: PASSED' : "check_owl_speech: #{$failures} FAILED"
exit($failures.zero? ? 0 : 1)
