require_relative './ffmpeg'
require_relative './util'

require 'fileutils'
require 'tmpdir'

DEFAULT_LANG = 'eng'
RAND_NAME_LENGTH = 32

def stripFile(lang, path)
   streams = FFMPEG.getStreams(path)

   if (streams[:audio].size() == 1)
      puts "ERROR: Only one audio stream. Will not strip. #{path}"
      return
   end

   targetId = nil
   streams[:audio].each{|audioStream|
      if (audioStream['language'] == lang)
         if (targetId != nil)
            puts "ERROR: Multiple matching audio streams found. #{path}"
            return
         end

         targetId = audioStream['index'].to_i()
      end
   }

   if (targetId == nil)
      puts "ERROR: Could not locate target audio stream. #{path}"
      return
   end

   streamCount = streams[:video].size() + streams[:audio].size() + streams[:subtitle].size() + streams[:other].size()

   args = [
      '-c:a', 'copy',
      '-c:v', 'copy',
      '-c:s', 'copy'
   ]

   (0...streamCount).each{|streamId|
      if (streamId == targetId)
         next
      end

      args += ['-map', "0:#{streamId}"]
   }

   tempPath = File.join(Dir.tmpdir, Util.randString(RAND_NAME_LENGTH) + File.extname(path))
   FFMPEG.transcode(path, tempPath, args)
   FileUtils.mv(tempPath, path)
end

def main(lang, targets)
   tasks = []
   labels = []

   targets.each{|target|
      tasks << Proc.new{ stripFile(lang, target) }
      labels << target
   }

   Util.parallel(tasks, labels, true, 2)
end

def parseArgs(args)
   if (args.size() == 0 || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
      puts "USAGE: ruby #{$0} --lang <lang> <file> ..."
      puts "Strip an audio stream from a file."
      puts "By default, the stream with the '#{DEFAULT_LANG}' language will be removed."
      exit(1)
   end

   targets = []
   lang = DEFAULT_LANG

   while (args.size() > 0)
      arg = args.shift()
      if (arg == '--lang')
         lang = args.shift()
      else
         targets << arg
      end
   end

   return lang, targets
end

if (__FILE__ == $0)
   main(*parseArgs(ARGV))
end
