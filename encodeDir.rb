require_relative './ffmpeg'
require_relative './vp9'

require 'fileutils'

DIRENT_TYPE_DIR = 'dir'
DIRENT_TYPE_FILE = 'file'

# Recursivley parse a dir and get info about the contents.
# Return: {
#     :type => DIRENT_TYPE_DIR,
#     :name => dirname,
#     :path => absPath,
#     :contents = [ { ... }, ...]
# }
def parseDir(path, relativePath)
   if (!File.directory?(path))
      raise("Told to parse a path that is not a dir: #{path}")
   end

   relativePath = File.join(relativePath, File.basename(path))

   contents = []
   dirsToExplore = []

   Dir.foreach(path).to_a().sort().each{|dirent|
      if (dirent == '.' || dirent == '..')
         next
      end

      direntPath = File.join(path, dirent)
      if (File.directory?(direntPath))
         dirsToExplore << direntPath
      else
         contents << {
            :type => DIRENT_TYPE_FILE,
            :name => File.basename(direntPath),
            :path => File.absolute_path(direntPath),
            :relPath => File.join(relativePath, dirent),
            :ext => File.extname(direntPath).sub(/^\./, '').downcase()
         }
      end
   }

   dirsToExplore.each{|dirPath|
      contents << parseDir(dirPath, relativePath)
   }

   return {
      :type => DIRENT_TYPE_DIR,
      :name => File.basename(path),
      :path => File.absolute_path(path),
      :relPath => relativePath,
      :contents => contents
   }
end

# Figure out the work that needs to be done.
# Returns: [[directories to make], [files to copy], [subtitles to encoce (to webvtt)], [files to encode]]
def splitWork(dirInfo)
   dirs = [dirInfo[:relPath]]
   toCopy = []
   subsToEncode = []
   toEncode = []

   dirInfo[:contents].each{|dirent|
      if (dirent[:type] == DIRENT_TYPE_DIR)
         tempDirs, tempToCopy, tempSubsToEncode, tempToEncode = splitWork(dirent)

         dirs += tempDirs
         toCopy += tempToCopy
         subsToEncode += tempSubsToEncode
         toEncode += tempToEncode
      else
         if (dirent[:ext] != 'webm' && FFMPEG::VIDEO_EXTENSIONS.include?(dirent[:ext]))
            toEncode << dirent
         elsif (dirent[:ext] != 'vtt' && FFMPEG::SUBTITLE_EXTENSIONS.include?(dirent[:ext]))
            subsToEncode << dirent
         else
            toCopy << dirent
         end
      end
   }

   return dirs, toCopy, subsToEncode, toEncode
end

def makeDirs(outputDir, dirs)
   dirs.each{|dir|
      FileUtils.mkdir_p(File.join(outputDir, dir))
   }
end

def copy(outputDir, files)
   files.each{|file|
      outPath = File.join(outputDir, file[:relPath])

      if (File.exists?(outPath))
         puts "SKIPPING: Copy target already exists: #{outPath}"
      else
         FileUtils.cp(file[:path], outPath)
      end
   }
end

# Get the streams for each video file and throw on any ones that are hard to encode.
def getStreams(files)
   violations = Hash.new{|hash, key| hash[key] = []}

   files.each{|file|
      file[:streams] = FFMPEG.getStreams(file[:path])

      if (file[:streams][:video].size() == 0)
         violations['no video streams'] << file
      end

      if (file[:streams][:audio].size() == 0)
         violations['no audio streams'] << file
      end

      if (file[:streams][:video].size() > 1)
         violations['multiple video streams'] << file
      end

      file[:streams][:subtitle].each{|subStream|
         if (!FFMPEG::KNOWN_SUBTITLE_CODECS.include?(subStream['codec_name']))
            violations['unknown sub type'] << file
         end
      }
   }

   if (violations.size() > 0)
      reasons = violations.to_a().map{|reason, files| "{#{reason}: [#{files.map{|file| file[:path]}.join(', ')}]}"}
      raise("Found files we cannot encode -- #{reasons}")
   end
end

def encodeSubs(outputDir, files)
   tasks = []
   labels = []

   # Check for conflicts and rename any conflicts.
   nameCount = Hash.new{|hash, key| hash[key] = 0}

   files.each{|file|
      outPath = File.join(outputDir, file[:relPath].sub(/#{File.extname(file[:relPath])}$/, '.vtt'))
      nameCount[outPath] += 1

      originalPath = outPath
      while (nameCount[outPath] > 1)
         outPath = File.join(outputDir, file[:relPath].sub(/#{File.extname(file[:relPath])}$/, ".#{nameCount[originalPath]}.vtt"))
      end

      if (File.exists?(outPath))
         puts "SKIPPING: Sub encode target already exists: #{outPath}"
      else
         tasks << Proc.new{ VP9.transcodeSubtitleFile(file[:path], outPath) }
         labels << file[:path]
      end
   }

   Util.parallel(tasks, labels, true)
end

# Get the subtitle streams from the file.
# Return an array of the stream ids.
def extractSubStreams(file)
   subStreams = []

   file[:streams][:subtitle].each{|subStream|
      if (FFMPEG::UNCONVERTABLE_SUBTITLE_CODECS.include?(subStream['codec_name']))
         next
      elsif (FFMPEG::CONVERTABLE_SUBTITLE_CODECS.include?(subStream['codec_name']))
         subStreams << subStream['index'].to_i()
      else
         raise("Unknown subtitle codec: #{subStream['codec_name']}")
      end
   }

   return subStreams
end

def encodeFiles(outputDir, files)
   tasks = []
   labels = []

   files.each{|file|
      outPath = File.join(outputDir, file[:relPath].sub(/#{File.extname(file[:relPath])}$/, '.webm'))

      if (File.exists?(outPath))
         puts "SKIPPING: Video encode target already exists: #{outPath}"
         next
      end

      subs = extractSubStreams(file)

      # Remember that multiple video or audio streams has been disallowed.
      videoStreamId = file[:streams][:video][0]['index'].to_i()
      audioStreamId = file[:streams][:audio][0]['index'].to_i()

      tasks << Proc.new{ VP9.transcodeWithSubs(file[:path], outPath, videoStreamId, audioStreamId, subs) }
      labels << file[:path]
   }

   Util.parallel(tasks, labels, true)
end

def main(targetDir, outputDir)
   dirInfo = parseDir(targetDir, '.')

   dirs, toCopy, subsToEncode, toEncode = splitWork(dirInfo)

   # Before doing any file operations, make sure any encode files look clean.
   getStreams(toEncode)

   # Dry run.
   if (outputDir == nil)
      return
   end

   makeDirs(outputDir, dirs)
   copy(outputDir, toCopy)
   encodeFiles(outputDir, toEncode)
   encodeSubs(outputDir, subsToEncode)
end

def parseArgs(args)
   if (![1, 2].include?(args.size()) || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
      puts "USAGE: ruby #{$0} <target dir> <output dir>"
      puts "       ruby #{$0} <target dir>"
      puts "Make a copy of <target dir> inside of <output dir> with all video files transcoded as webm."
      puts "All non-video files will be directly copied over."
      puts "If there is any reason the directory cannot be easily encoded, we will panic before any"
      puts "encoding or copying is done."
      puts "If no output directory is supplied, then a dry run will be performed where no files are copied or encoded."
      exit(1)
   end

   targetDir = args.shift()

   outputDir = nil
   if (args.size() > 0)
      outputDir = args.shift()
   end

   return targetDir, outputDir
end

if (__FILE__ == $0)
   main(*parseArgs(ARGV))
end
