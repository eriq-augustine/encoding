require_relative './ffmpeg'

module VP9
   DEFAULT_ARGS = [
      '-c:v', 'libvpx-vp9',
      '-crf', '32', '-b:v', '0',
      '-c:a', 'libvorbis', '-b:a', '64k',
      '-cpu-used', '1',
      '-deadline', '-good',
      '-tile-columns', '6', '-frame-parallel', '1',
      '-auto-alt-ref', '1', '-lag-in-frames', '25',
      '-max_muxing_queue_size', '9999',
      '-f', 'webm'
   ]

   DEFAULT_SUB_ARGS = [
      '-c:s', 'webvtt'
   ]

   def VP9.transcode(inPath, outPath, additionalArgs = [])
      FFMPEG.transcode(inPath, outPath, DEFAULT_ARGS + additionalArgs)
   end

   # Extract the subs as well as standard encoding.
   def VP9.transcodeWithSubs(inPath, outPath, subStreamIds)
      args = []
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
         exit(1)
      end

      inPath = args.shift()
      outPath = args.shift()

      return inPath, outPath
   end
end

if (__FILE__ == $0)
   VP9.transcode(*VP9.parseArgs(ARGV))
end
