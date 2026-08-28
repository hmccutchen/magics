require_relative '../../app/config.rb'
require_relative '../../app/assets.rb'

# The push walk is two frames per direction -- feet planted, then mid-stride --
# advanced by ground covered rather than by a timer. These check the pieces
# that have to line up for that to read as walking rather than sliding.

$failures = 0

def check label, got, want
  if got == want
    puts "  PASS  #{label}"
  else
    puts "  FAIL  #{label}  (got #{got.inspect}, want #{want.inspect})"
    $failures += 1
  end
end

ROOT = File.join __dir__, '../..'

puts 'every push pose is a two-frame cycle, planted then striding'
Assets::PUSH_POSE_FILES.each_key do |name|
  paths = Assets.descriptor(name, :myth)[:paths]

  check "#{name} has two frames", paths.length, 2
  check "#{name} starts planted", paths[0].include?('pushing/'), false
  check "#{name} then strides",   paths[1].include?('pushing/'), true
end

puts 'and every frame is a file that exists'
Assets::PUSH_POSE_FILES.each_key do |name|
  Assets.descriptor(name, :myth)[:paths].each do |path|
    check path, File.exist?(File.join(ROOT, path)), true
  end
end

puts 'both frames of a pose are reachable as the cycle turns over'
Assets::PUSH_POSE_FILES.each_key do |name|
  seen = (0..20).map { |i| Assets.frame_path name, :myth, i / 20.0 }.uniq

  check "#{name} shows both", seen.length, 2
end

puts 'the walk cycle is untouched'
walk = Assets.descriptor :player_walk, :myth
check 'still eight frames', walk[:paths].length, 8
check 'still its own cadence', Config::WALK_CYCLE_DISTANCE, 160.0

puts 'the distance accumulator wraps without skipping either cycle'
#
# walk_distance is wrapped to keep it bounded over a long session. If that
# wrap is not a whole number of BOTH cycles, the animation jumps a frame every
# time it comes round -- once per wrap, which is exactly the kind of thing
# that gets blamed on the art.
wrap = Config::WALK_CYCLE_DISTANCE * Config::PUSH_CYCLE_DISTANCE
check 'a whole number of walk cycles',
      (wrap % Config::WALK_CYCLE_DISTANCE).abs < 0.0001, true
check 'a whole number of push cycles',
      (wrap % Config::PUSH_CYCLE_DISTANCE).abs < 0.0001, true

puts 'the push cycle is shorter than the walk, so two frames do not drag'
check 'shorter', Config::PUSH_CYCLE_DISTANCE < Config::WALK_CYCLE_DISTANCE, true

puts
puts $failures.zero? ? 'check_push_walk: PASSED' : "check_push_walk: #{$failures} FAILED"
exit($failures.zero? ? 0 : 1)
