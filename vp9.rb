require_relative './ffmpeg'

# FFMPG VP9 Documentation: https://trac.ffmpeg.org/wiki/Encode/VP9
# Google VP9 Recommendations: https://developers.google.com/media/vp9/settings/vod
# This library will first attempt to find the frame size and rate to use Google's recommended Constrained Quality setting.
# But if there is an issue, it will fallback to Constant Quality.

module VP9
   DEFAULT_ARGS = [
      # Video args are handled in VP9.getVideoArgs().
      '-c:a', 'libvorbis', '-minrate', '128k',
      '-g', '240',  # Keyframe spacing.
      '-cpu-used', '1',
      '-deadline', '-good',
      '-tile-columns', '6', '-frame-parallel', '1',
      '-auto-alt-ref', '1', '-lag-in-frames', '25',
      '-max_muxing_queue_size', '9999',
      '-f', 'webm'
   ]

   DEFAULT_CRF = 30

   DEFAULT_SUB_ARGS = [
      '-c:s', 'webvtt'
   ]

   # {resolution => {high/low frame rate => target bitrate (kbps), ...}, ...}
   TARGET_BITRATE = {
      '640x360' =>   {false => 276,   true => 750},
      '1280x720' =>  {false => 1024,  true => 1800},
      '1920x1080' => {false => 1800,  true => 3000},
      '2560x1440' => {false => 6000,  true => 9000},
      '3840x2160' => {false => 12000, true => 18000}
   }

   MIN_BITRATE_RATIO = 0.50
   MAX_BITRATE_RATIO = 1.45

   def VP9.getVideoArgs(inPath)
      args = ['-c:v', 'libvpx-vp9']
      fallbackArgs = args + ['-crf', "#{DEFAULT_CRF}", '-b:v', '0']

      streams = FFMPEG.getStreams(inPath)
      if (streams[:video].size() != 1)
         puts "Found multiple video streams, falling back to constant quality."
         return fallbackArgs
      end

      stream = streams[:video][0]

      if (!stream.include?('width') || !stream.include?('height'))
         puts "Could not discover video resolution, falling back to constant quality."
         return fallbackArgs
      end

      resolution = "#{stream['width']}x#{stream['height']}"
      if (!TARGET_BITRATE.include?(resolution))
         puts "Non-standard resolution (#{resolution}), falling back to constant quality."
         return fallbackArgs
      end

      highFrameRate = false
      if (stream.include?('avg_frame_rate'))
         frameRateString = stream['avg_frame_rate']
         # HACK(eriq): ffmpeg lists the frame rate as a division, e.g. "30000/1001".
         #  We should really figure out how to do this without eval, as it's a huge vulnerability.
         frameRate = eval(frameRateString).to_i()

         highFrameRate = (frameRate > 40)
      end

      targetBitrate = TARGET_BITRATE[resolution][highFrameRate]
      minBitrate = (targetBitrate * MIN_BITRATE_RATIO).ceil()
      maxBitrate = (targetBitrate * MAX_BITRATE_RATIO).ceil()

      args += ['-vf', 'scale=1920x1080']
      args += ['-b:v', "#{targetBitrate}k", '-minrate', "#{minBitrate}k", '-maxrate', "#{maxBitrate}k"]
      args += ['-crf', "#{DEFAULT_CRF}"]

      return args
   end

   def VP9.transcode(inPath, outPath, additionalArgs = [])
      videoArgs = VP9.getVideoArgs(inPath)
      FFMPEG.transcode(inPath, outPath, videoArgs + DEFAULT_ARGS + additionalArgs)
   end

   # Extract the subs as well as standard encoding.
   def VP9.transcodeWithSubs(inPath, outPath, videoStreamId, audioStreamIds, subStreamIds)
      args = [
         '-map', "0:#{videoStreamId}"
      ]

      audioStreamIds.each{|id|
         args += ['-map', "0:#{id}"]
      }

      subStreamIds.each{|id|
         args += ['-map', "0:#{id}", '-c:s', 'webvtt']
      }

      VP9.transcode(inPath, outPath, args)
      FFMPEG.extractSubs(inPath, File.dirname(outPath), subStreamIds, 'webvtt', 'vtt')
   end

   def VP9.transcodeSubtitleFile(inPath, outPath)
      FFMPEG.transcode(inPath, outPath, DEFAULT_SUB_ARGS)
   end

   def VP9.parseArgs(args)
      if (args.size != 2 || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
         puts "USAGE: ruby #{$0} <in path> <out path>"
         puts "Encode a file using our default VP9 options."
         puts "Will also utilize all but one of the availble processors."
         exit(1)
      end

      inPath = args.shift()
      outPath = args.shift()
      additionalArgs = ['-threads', [1, Etc.nprocessors - 1].max()]

      return inPath, outPath, additionalArgs
   end
end

if (__FILE__ == $0)
   VP9.transcode(*VP9.parseArgs(ARGV))
end
