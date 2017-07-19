require_relative './ffmpeg'

module VP9
   DEFAULT_ARGS = [
      '-c:v', 'libvpx-vp9',
      '-crf', '31', '-b:v', '0',
      '-c:a', 'libvorbis', '-b:a', '64k',
      '-cpu-used', '1',
      '-deadline', '-good',
      '-tile-columns', '6', '-frame-parallel', '1',
      '-auto-alt-ref', '1', '-lag-in-frames', '25',
      '-max_muxing_queue_size', '9999',
      '-f', 'webm'
   ]

   def VP9.transcode(inPath, outPath)
      FFMPEG.transcode(inPath, outPath, DEFAULT_ARGS)
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
