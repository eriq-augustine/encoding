require_relative './ffmpeg'
require_relative './util'

require 'fileutils'
require 'tmpdir'

RAND_NAME_LENGTH = 32

def stripFile(path)
   streams = FFMPEG.getStreams(path)

   if (streams[:subtitle].size() == 0)
      return
   end

   args = [
      '-c:a', 'copy',
      '-c:v', 'copy',
   ]

   streams.each{|label, streams|
      if ([:metadata, :subtitle].include?(label))
         next
      end

      streams.each{|stream|
         args += ['-map', "0:#{stream['index'].to_i()}"]
      }
   }

   tempPath = File.join(Dir.tmpdir, Util.randString(RAND_NAME_LENGTH) + File.extname(path))
   FFMPEG.transcode(path, tempPath, args)
   FileUtils.mv(tempPath, path)
end

def main(targets)
   tasks = []
   labels = []

   targets.each{|target|
      tasks << Proc.new{ stripFile(target) }
      labels << target
   }

   Util.parallel(tasks, labels, true, 2)
end

def parseArgs(args)
   if (args.size() == 0 || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
      puts "USAGE: ruby #{$0} <file> ..."
      puts "Strip all subtitle streams from a file."
      exit(1)
   end

   targets = args

   return [targets]
end

if (__FILE__ == $0)
   main(*parseArgs(ARGV))
end
